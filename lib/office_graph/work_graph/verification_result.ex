defmodule OfficeGraph.WorkGraph.VerificationResult.ValidateEvidenceCheckMatch do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.WorkGraph.EvidenceItem

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    verification_check_id = Ash.Changeset.get_attribute(changeset, :verification_check_id)
    evidence_item_id = Ash.Changeset.get_attribute(changeset, :evidence_item_id)

    cond do
      is_nil(verification_check_id) or is_nil(evidence_item_id) ->
        changeset

      evidence_matches_check?(evidence_item_id, verification_check_id) ->
        changeset

      true ->
        Ash.Changeset.add_error(changeset,
          field: :evidence_item_id,
          message: "must belong to verification_check_id"
        )
    end
  end

  defp evidence_matches_check?(evidence_item_id, verification_check_id) do
    EvidenceItem
    |> Ash.Query.filter(id == ^evidence_item_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{verification_check_id: ^verification_check_id}} -> true
      {:ok, _missing_or_mismatch} -> false
      {:error, _error} -> true
    end
  end
end

defmodule OfficeGraph.WorkGraph.VerificationResult do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "verification_results"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false, public?: true, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :evidence_item_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :result, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :verification_check_id,
        :evidence_item_id,
        :operation_id,
        :result
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
                evidence_item_id: OfficeGraph.WorkGraph.EvidenceItem,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}

      change OfficeGraph.WorkGraph.VerificationResult.ValidateEvidenceCheckMatch
    end
  end

  identities do
    identity :unique_verification_check, [:verification_check_id]
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :verification_complete}
    end
  end

  graphql do
    type :verification_result
  end

  json_api do
    type "verification_result"
  end
end
