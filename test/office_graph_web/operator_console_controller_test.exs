defmodule OfficeGraphWeb.OperatorConsoleControllerTest do
  use OfficeGraphWeb.ConnCase, async: false

  setup_all do
    react_router_static_assets_dir()
    |> File.rm_rf!()

    react_router_static_assets_dir()
    |> Path.join("assets")
    |> File.mkdir_p!()

    File.write!(react_router_static_index_path(), react_router_fixture_index_html())

    File.write!(
      react_router_build_asset_path("/assets/react-router/assets/operator-test.css"),
      ""
    )

    File.write!(
      react_router_build_asset_path("/assets/react-router/assets/operator-test.js"),
      "window.__operatorConsoleFixture = true;\n"
    )

    on_exit(fn ->
      react_router_static_assets_dir()
      |> File.rm_rf!()
    end)

    :ok
  end

  test "serves the React Router operator console app shell", %{conn: conn} do
    html =
      conn
      |> get(~p"/operator")
      |> html_response(200)

    assert html =~ "window.__reactRouterContext"
    assert html =~ "Office Graph"
    assert react_router_asset_paths(html) != []

    assert Enum.all?(
             react_router_asset_paths(html),
             &String.starts_with?(&1, "/assets/react-router/")
           )

    refute html =~ ~s(id="operator-console-root")
    refute html =~ ~s(href="/assets/operator/main.css")
    refute html =~ ~s(src="/assets/operator/main.js")
    refute html =~ "data-phx-main"
    refute html =~ "live_socket"
  end

  test "app shell assets match the React Router build contract", %{conn: conn} do
    html =
      conn
      |> get(~p"/operator")
      |> html_response(200)

    shell_asset_paths = react_router_asset_paths(html)

    assert "/assets/operator/main.css" not in shell_asset_paths
    assert "/assets/operator/main.js" not in shell_asset_paths
    assert Enum.any?(shell_asset_paths, &String.ends_with?(&1, ".js"))
    assert Enum.any?(shell_asset_paths, &String.ends_with?(&1, ".css"))

    for asset_path <- shell_asset_paths do
      assert File.exists?(react_router_build_asset_path(asset_path)),
             "Expected React Router build asset #{asset_path} to exist"
    end

    assert File.exists?("assets/package.json"),
           "Frontend package metadata must live under assets/package.json"

    assert File.exists?("assets/pnpm-lock.yaml"),
           "Frontend dependency lockfile must live under assets/pnpm-lock.yaml"

    assert File.exists?("assets/vite.react-router.config.ts"),
           "Frontend React Router Vite config must live under assets/vite.react-router.config.ts"

    assert File.exists?(react_router_static_index_path()),
           "React Router app shell must be staged into priv/static/assets/react-router/index.html"

    package_json = File.read!("assets/package.json")
    aliases = Mix.Project.config()[:aliases]

    assert package_json =~ ~s("packageManager": "pnpm@)
    assert package_json =~ ~s("verify:app-shell")

    assert package_json =~
             ~s("router:build": "react-router build --config vite.react-router.config.ts")

    assert package_json =~ ~s("router:deploy": "pnpm run router:build)
    assert package_json =~ "pnpm run router:deploy && pnpm run verify:app-shell"
    assert aliases[:setup] == ["deps.get", "assets.setup", "ecto.setup"]
    assert aliases[:"assets.setup"] == ["cmd --cd assets pnpm install --frozen-lockfile"]

    assert aliases[:"assets.build"] == [
             "assets.setup",
             "cmd --cd assets pnpm run build",
             "cmd --cd assets pnpm run router:deploy",
             "cmd --cd assets pnpm run verify:app-shell"
           ]

    assert aliases[:"assets.deploy"] == ["assets.build", "phx.digest"]
    assert aliases[:"frontend.verify"] == ["assets.setup", "cmd --cd assets pnpm run verify"]
    assert aliases[:release] == ["assets.deploy", "release"]

    assert OfficeGraph.MixProject.cli()[:preferred_envs][:verify] == :test
  end

  test "serves React Router build assets referenced by the app shell", %{conn: conn} do
    html =
      conn
      |> get(~p"/operator")
      |> html_response(200)

    asset_path = Enum.find(react_router_asset_paths(html), &String.ends_with?(&1, ".js"))

    assert asset_path

    conn
    |> get(asset_path)
    |> response(200)
  end

  test "operator app shell fails when required React Router build assets are missing", %{
    conn: conn
  } do
    missing_asset = react_router_build_asset_to_move!()
    on_exit(fn -> restore_moved_asset(missing_asset) end)

    File.rename!(missing_asset.path, missing_asset.backup_path)

    body =
      conn
      |> get(~p"/operator")
      |> response(503)

    assert body =~ "Operator console assets are missing"
    assert body =~ missing_asset.asset_path
  end

  defp react_router_asset_paths(html) do
    ~r/(?:href|src)="([^"]+)"|import\s+["']([^"']+)["']/
    |> Regex.scan(html)
    |> Enum.map(fn [_match | captures] -> Enum.find(captures, &(&1 != "")) end)
    |> Enum.filter(&String.starts_with?(&1, "/assets/"))
    |> Enum.uniq()
  end

  defp react_router_build_asset_to_move! do
    html = File.read!(react_router_static_index_path())

    asset_path =
      html
      |> react_router_asset_paths()
      |> Enum.find(&String.ends_with?(&1, ".js"))

    assert asset_path, "Expected React Router index.html to reference a JavaScript asset"

    path = react_router_build_asset_path(asset_path)
    backup_path = path <> ".missing-test"

    assert File.exists?(path),
           "Expected React Router build asset #{asset_path} to exist at #{path}"

    refute_backup_exists(backup_path)

    %{asset_path: asset_path, path: path, backup_path: backup_path}
  end

  defp react_router_static_index_path do
    Path.join(react_router_static_assets_dir(), "index.html")
  end

  defp react_router_build_asset_path(asset_path) do
    Path.join(
      react_router_static_assets_dir(),
      String.replace_prefix(asset_path, "/assets/react-router/", "")
    )
  end

  defp react_router_static_assets_dir do
    Application.app_dir(:office_graph, "priv/static/assets/react-router")
  end

  defp restore_moved_asset(%{path: path, backup_path: backup_path}) do
    if File.exists?(backup_path) do
      File.rename!(backup_path, path)
    end
  end

  defp refute_backup_exists(backup_path) do
    refute File.exists?(backup_path),
           "Refusing to overwrite existing missing-asset backup #{backup_path}"
  end

  defp react_router_fixture_index_html do
    """
    <!doctype html>
    <html>
      <head>
        <meta charset="UTF-8">
        <title>Office Graph</title>
        <link rel="stylesheet" href="/assets/react-router/assets/operator-test.css">
      </head>
      <body>
        <script>window.__reactRouterContext = {};</script>
        <script type="module" src="/assets/react-router/assets/operator-test.js"></script>
      </body>
    </html>
    """
  end
end
