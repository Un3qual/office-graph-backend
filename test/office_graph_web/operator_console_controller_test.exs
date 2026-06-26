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
end
