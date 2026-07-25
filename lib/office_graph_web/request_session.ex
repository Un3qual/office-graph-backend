defmodule OfficeGraphWeb.RequestSession do
  @moduledoc false

  alias OfficeGraph.Identity.SessionContext

  def resolve_resolution(%{context: context}) do
    context
    |> Map.get(:actor)
    |> resolve()
  end

  def resolve(%SessionContext{} = session_context), do: {:ok, session_context}

  def resolve(nil), do: {:error, :forbidden}

  def resolve(_actor), do: {:error, {:invalid_field, :session_context}}
end
