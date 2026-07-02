defmodule OfficeGraphWeb.RequestSession do
  @moduledoc false

  alias OfficeGraph.ApiSupport
  alias OfficeGraph.Identity.SessionContext

  def resolve(%SessionContext{} = session_context), do: {:ok, session_context}

  def resolve(nil) do
    with {:ok, %{session: session}} <- ApiSupport.bootstrap_local_api_owner() do
      {:ok, session}
    end
  end

  def resolve(_actor), do: {:error, {:invalid_field, :session_context}}
end
