defmodule OfficeGraphWeb.OperatorConsoleControllerTest do
  use OfficeGraphWeb.ConnCase, async: true

  test "serves the React operator console app shell", %{conn: conn} do
    html =
      conn
      |> get(~p"/operator")
      |> html_response(200)

    assert html =~ ~s(id="operator-console-root")
    assert html =~ "Operator Console"
    assert html =~ ~s(href="/assets/operator/main.css")
    assert html =~ ~s(src="/assets/operator/main.js")
    refute html =~ "data-phx-main"
    refute html =~ "live_socket"
  end

  test "app shell assets match the frontend build contract", %{conn: conn} do
    html =
      conn
      |> get(~p"/operator")
      |> html_response(200)

    assert app_shell_asset_paths(html) == [
             "/assets/operator/main.css",
             "/assets/operator/main.js"
           ]

    assert File.exists?("assets/package.json"),
           "Frontend package metadata must live under assets/package.json"

    assert File.exists?("assets/pnpm-lock.yaml"),
           "Frontend dependency lockfile must live under assets/pnpm-lock.yaml"

    assert File.exists?("assets/vite.config.ts"),
           "Frontend Vite config must live under assets/vite.config.ts"

    package_json = File.read!("assets/package.json")
    vite_config = File.read!("assets/vite.config.ts")
    aliases = Mix.Project.config()[:aliases]

    assert package_json =~ ~s("packageManager": "pnpm@)
    assert package_json =~ ~s("verify:app-shell")
    assert package_json =~ ~s("build": "vite build")
    assert vite_config =~ ~s(outDir: "../priv/static")
    assert vite_config =~ ~s|resolve(__dirname, "src/main.tsx")|
    assert vite_config =~ ~s|entryFileNames: "assets/operator/[name].js"|
    assert vite_config =~ ~s|assetFileNames: "assets/operator/[name][extname]"|
    assert aliases[:setup] == ["deps.get", "assets.setup", "ecto.setup"]
    assert aliases[:"assets.setup"] == ["cmd --cd assets pnpm install --frozen-lockfile"]
    assert aliases[:"assets.build"] == ["assets.setup", "cmd --cd assets pnpm run build"]
    assert aliases[:"assets.deploy"] == ["assets.build", "phx.digest"]
    assert aliases[:"frontend.verify"] == ["assets.setup", "cmd --cd assets pnpm run verify"]
    assert aliases[:release] == ["assets.deploy", "release"]

    assert OfficeGraph.MixProject.cli()[:preferred_envs][:verify] == :test
  end

  defp app_shell_asset_paths(html) do
    ~r/(?:href|src)="([^"]+)"/
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.filter(&String.starts_with?(&1, "/assets/operator/"))
  end
end
