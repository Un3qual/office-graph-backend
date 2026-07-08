defmodule OfficeGraph.WorkGraph.Queries do
  @moduledoc false

  alias OfficeGraph.WorkGraph.{Signal, VerificationCheck}

  require Ash.Query

  def graphql_node_type(%Signal{}), do: :signal
  def graphql_node_type(_value), do: nil

  def graphql_node(session_context, :signal, id) do
    Ash.get(Signal, id, actor: session_context, not_found_error?: false)
  end

  def graphql_node(_session_context, _type, _id), do: {:ok, nil}

  def get_verification_check(session_context, id) do
    VerificationCheck
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(actor: session_context)
    |> case do
      {:ok, nil} -> {:error, {:missing_verification_check, id}}
      {:ok, verification_check} -> {:ok, verification_check}
      {:error, _error} -> {:error, {:missing_verification_check, id}}
    end
  end
end
