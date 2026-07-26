defmodule OfficeGraphWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use OfficeGraphWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint OfficeGraphWeb.Endpoint

      use OfficeGraphWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import OfficeGraphWeb.ConnCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(OfficeGraph.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    conn = Phoenix.ConnTest.build_conn()

    if tags[:unauthenticated] do
      {:ok, conn: conn}
    else
      {:ok, fixture} = OfficeGraph.ApiSupport.bootstrap_local_human_session()

      {:ok,
       conn:
         conn
         |> Plug.Test.init_test_session(%{
           human_session_id: fixture.human_session.session.id
         })
         |> Plug.Conn.put_req_header("origin", OfficeGraphWeb.Endpoint.url()),
       human_session: fixture.human_session.session_context}
    end
  end

  def without_human_session(conn) do
    conn
    |> Plug.Conn.fetch_session()
    |> Plug.Conn.delete_session(:human_session_id)
  end

  def recycle_human_session(conn) do
    session_id = Plug.Conn.get_session(conn, :human_session_id)

    conn
    |> Phoenix.ConnTest.recycle()
    |> Plug.Test.init_test_session(%{human_session_id: session_id})
    |> Plug.Conn.put_req_header("origin", OfficeGraphWeb.Endpoint.url())
  end
end
