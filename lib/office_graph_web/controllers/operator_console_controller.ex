defmodule OfficeGraphWeb.OperatorConsoleController do
  use OfficeGraphWeb, :controller

  @required_assets [
    "/assets/operator/main.css",
    "/assets/operator/main.js"
  ]

  def index(conn, _params) do
    case missing_assets() do
      [] ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, app_shell())

      missing_assets ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          503,
          "Operator console assets are missing: #{Enum.join(missing_assets, ", ")}"
        )
    end
  end

  defp app_shell do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Office Graph Operator Console</title>
        <link rel="stylesheet" href="/assets/operator/main.css">
      </head>
      <body>
        <noscript>JavaScript is required to run the Office Graph Operator Console.</noscript>
        <div id="operator-console-root" aria-label="Operator Console"></div>
        <script type="module" src="/assets/operator/main.js"></script>
      </body>
    </html>
    """
  end

  defp missing_assets do
    Enum.reject(@required_assets, fn asset_path ->
      asset_path
      |> static_asset_path()
      |> File.exists?()
    end)
  end

  defp static_asset_path(asset_path) do
    Application.app_dir(
      :office_graph,
      Path.join("priv/static", String.trim_leading(asset_path, "/"))
    )
  end
end
