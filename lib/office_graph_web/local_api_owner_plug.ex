defmodule OfficeGraphWeb.LocalApiOwnerPlug do
  @moduledoc false

  @behaviour Plug

  alias OfficeGraph.ApiSupport

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case ApiSupport.bootstrap_local_api_owner() do
      {:ok, %{session: session}} -> Ash.PlugHelpers.set_actor(conn, session)
      {:error, _reason} -> conn
    end
  end
end
