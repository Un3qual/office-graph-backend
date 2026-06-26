defmodule OfficeGraphWeb.OperatorConsoleController do
  use OfficeGraphWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, app_shell())
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
end
