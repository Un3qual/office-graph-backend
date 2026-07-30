defmodule OfficeGraph.EnterpriseIdentity.ActionSupport do
  @moduledoc false

  alias OfficeGraph.CommandSupport

  @rollback_marker :enterprise_identity_action_error

  def rollback(resource, error) do
    Ash.DataLayer.rollback(resource, {@rollback_marker, error})
  end

  def normalize_action_result(result) do
    result
    |> CommandSupport.normalize_action_result()
    |> case do
      {:error, {@rollback_marker, error}} -> {:error, error}
      result -> result
    end
  end
end
