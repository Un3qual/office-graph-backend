defmodule OfficeGraphWeb.OperatorConsoleControllerTest do
  use OfficeGraphWeb.ConnCase, async: false

  setup_all do
    original_static_root = Application.fetch_env(:office_graph, :operator_console_static_root)
    static_root = temporary_static_root()

    Application.put_env(:office_graph, :operator_console_static_root, static_root)

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
      File.rm_rf!(static_root)
      restore_static_root(original_static_root)
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

  test "serves the React Router packet workspace app shell", %{conn: conn} do
    html =
      conn
      |> get(~p"/packets")
      |> html_response(200)

    assert html =~ "window.__reactRouterContext"
    assert html =~ "Office Graph"
    assert react_router_asset_paths(html) != []

    assert Enum.all?(
             react_router_asset_paths(html),
             &String.starts_with?(&1, "/assets/react-router/")
           )

    refute html =~ "data-phx-main"
    refute html =~ "live_socket"
  end

  test "serves the React Router all-runs workspace app shell", %{conn: conn} do
    html =
      conn
      |> get(~p"/runs")
      |> html_response(200)

    assert html =~ "window.__reactRouterContext"
    assert html =~ "Office Graph"
    assert react_router_asset_paths(html) != []

    assert Enum.all?(
             react_router_asset_paths(html),
             &String.starts_with?(&1, "/assets/react-router/")
           )

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
    vite_react_router_config = File.read!("assets/vite.react-router.config.ts")
    aliases = Mix.Project.config()[:aliases]

    assert package_json =~ ~s("packageManager": "pnpm@)
    assert package_json =~ ~s("verify:app-shell")
    assert package_json =~ ~s("build": "react-router build --config vite.react-router.config.ts")
    assert package_json =~ ~s("dev": "react-router dev --config vite.react-router.config.ts)

    assert package_json =~ ~s("router:build": "pnpm run build")

    assert package_json =~ ~s("router:deploy": "pnpm run build)
    assert package_json =~ "pnpm run router:deploy && pnpm run verify:app-shell"
    assert vite_react_router_config =~ "reactRouter()"
    assert vite_react_router_config =~ "officeGraphBabelTransforms"
    refute vite_react_router_config =~ "@vitejs/plugin-react"
    refute vite_react_router_config =~ "react({"
    assert aliases[:setup] == ["deps.get", "assets.setup", "ecto.setup"]
    assert aliases[:"assets.setup"] == ["cmd --cd assets pnpm install --frozen-lockfile"]

    assert aliases[:"assets.build"] == [
             "assets.setup",
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

    asset_conn = get(conn, asset_path)

    assert get_resp_header(asset_conn, "cache-control") == [
             "public, max-age=31536000, immutable"
           ]

    response(asset_conn, 200)
  end

  test "product app shells fail when required React Router build assets are missing", %{
    conn: conn
  } do
    missing_asset = react_router_build_asset_to_move!()
    on_exit(fn -> restore_moved_asset(missing_asset) end)

    File.rename!(missing_asset.path, missing_asset.backup_path)

    for product_path <- ["/operator", "/packets", "/runs"] do
      body =
        conn
        |> recycle()
        |> get(product_path)
        |> response(503)

      assert body =~ "Operator console assets are missing"
      assert body =~ missing_asset.asset_path
    end
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
    :office_graph
    |> Application.fetch_env!(:operator_console_static_root)
    |> Path.join("assets/react-router")
  end

  defp temporary_static_root do
    Path.join(
      System.tmp_dir!(),
      "office-graph-operator-console-#{System.unique_integer([:positive])}"
    )
  end

  defp restore_static_root({:ok, static_root}) do
    Application.put_env(:office_graph, :operator_console_static_root, static_root)
  end

  defp restore_static_root(:error) do
    Application.delete_env(:office_graph, :operator_console_static_root)
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
