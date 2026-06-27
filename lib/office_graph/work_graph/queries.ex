defmodule OfficeGraph.WorkGraph.Queries do
  @moduledoc false

  alias OfficeGraph.WorkGraph.VerificationCheck

  require Ash.Query

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
