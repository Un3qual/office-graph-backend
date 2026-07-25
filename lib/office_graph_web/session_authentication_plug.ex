defmodule OfficeGraphWeb.SessionAuthenticationPlug do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias OfficeGraph.Authentication

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Ash.PlugHelpers.get_actor(conn) do
      nil ->
        load_cookie_session(conn)

      _already_assigned_actor ->
        conn
    end
  end

  defp load_cookie_session(conn) do
    case get_session(conn, :human_session_id) do
      session_id when is_binary(session_id) -> load_session(conn, session_id)
      _missing_session -> conn
    end
  end

  defp load_session(conn, session_id) do
    case Authentication.resolve_session(session_id) do
      {:ok, session_context} ->
        conn
        |> assign(:human_session, session_context)
        |> Ash.PlugHelpers.set_actor(session_context)

      {:error, :invalid_session} ->
        delete_session(conn, :human_session_id)

      {:error, :identity_storage_unavailable} ->
        conn
    end
  end
end
