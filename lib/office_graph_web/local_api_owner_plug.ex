defmodule OfficeGraphWeb.LocalApiOwnerPlug do
  @moduledoc false

  @behaviour Plug

  alias OfficeGraph.ApiSupport

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Ash.PlugHelpers.get_actor(conn) do
      nil ->
        case ApiSupport.bootstrap_local_api_owner() do
          {:ok, %{session: session}} -> Ash.PlugHelpers.set_actor(conn, session)
          {:error, _reason} -> conn
        end

      _actor ->
        conn
    end
  end
end
