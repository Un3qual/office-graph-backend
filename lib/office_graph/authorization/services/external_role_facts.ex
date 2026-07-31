defmodule OfficeGraph.Authorization.ExternalRoleFacts do
  @moduledoc false

  @callback login_scopes(principal_id :: String.t()) ::
              {:ok, [%{organization_id: String.t(), workspace_id: String.t()}]}
              | {:error, term()}

  @callback role_ids(
              principal_id :: String.t(),
              organization_id :: String.t(),
              workspace_id :: String.t() | nil,
              candidate_role_ids :: [String.t()]
            ) :: {:ok, [String.t()]} | {:error, term()}
end

defmodule OfficeGraph.Authorization.ExternalRoleFacts.Empty do
  @moduledoc false

  @behaviour OfficeGraph.Authorization.ExternalRoleFacts

  @impl true
  def login_scopes(_principal_id), do: {:ok, []}

  @impl true
  def role_ids(_principal_id, _organization_id, _workspace_id, _candidate_role_ids),
    do: {:ok, []}
end
