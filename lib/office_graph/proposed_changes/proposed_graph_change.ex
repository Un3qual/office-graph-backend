defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.TraceReferenceScope do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Integrations.NormalizedIntakeEvent
  alias OfficeGraph.Operations.OperationCorrelation

  require Ash.Query

  @trace_references [
    operation_id: OperationCorrelation,
    normalized_event_id: NormalizedIntakeEvent
  ]

  @impl true
  def change(changeset, _opts, _context) do
    with {:ok, organization_id, workspace_id} <- target_scope(changeset) do
      Enum.reduce(@trace_references, changeset, fn {field, resource}, changeset ->
        validate_reference(changeset, field, resource, organization_id, workspace_id)
      end)
    else
      :error ->
        changeset
        |> Ash.Changeset.add_error(
          field: :organization_id,
          message: "proposed change scope is required for trace references"
        )
        |> Ash.Changeset.add_error(
          field: :workspace_id,
          message: "proposed change scope is required for trace references"
        )
    end
  end

  defp target_scope(changeset) do
    organization_id = Ash.Changeset.get_attribute(changeset, :organization_id)
    workspace_id = Ash.Changeset.get_attribute(changeset, :workspace_id)

    if is_nil(organization_id) or is_nil(workspace_id) do
      :error
    else
      {:ok, organization_id, workspace_id}
    end
  end

  defp validate_reference(changeset, field, resource, organization_id, workspace_id) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      id ->
        case fetch_reference(resource, id) do
          {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id}} ->
            changeset

          {:ok, _missing_or_cross_scope} ->
            add_scope_error(changeset, field)

          {:error, error} ->
            Ash.Changeset.add_error(
              changeset,
              field: field,
              message: "#{field} lookup failed: #{format_lookup_error(error)}"
            )
        end
    end
  end

  defp fetch_reference(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one(authorize?: false)
  end

  defp add_scope_error(changeset, field) do
    Ash.Changeset.add_error(
      changeset,
      field: field,
      message: "#{field} must match proposed change scope"
    )
  end

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)
  defp format_lookup_error(error), do: inspect(error)
end

defmodule OfficeGraph.ProposedChanges.ProposedGraphChange do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.ProposedChanges.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "proposed_graph_changes"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "proposed_graph_changes_organization_id_fkey",
                      workspace_id: "proposed_graph_changes_workspace_id_fkey",
                      operation_id: "proposed_graph_changes_operation_id_fkey",
                      normalized_event_id: "proposed_graph_changes_normalized_event_id_fkey"
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :normalized_event_id, :uuid, public?: true
    attribute :status, :string, allow_nil?: false, default: "pending", public?: true
    attribute :change_type, :string, allow_nil?: false, public?: true
    attribute :payload, :map, allow_nil?: false, default: %{}, public?: true
    attribute :validation_errors, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :applied_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :operation_id,
        :normalized_event_id,
        :change_type,
        :payload
      ]

      change OfficeGraph.ProposedChanges.ProposedGraphChange.TraceReferenceScope
    end

    update :set_payload do
      require_atomic? false
      accept [:payload]
      validate attribute_equals(:status, "pending")
    end

    update :reject do
      require_atomic? false
      accept [:validation_errors]
      validate attribute_equals(:status, "pending")
      change set_attribute(:status, "rejected")
    end

    update :mark_applied do
      require_atomic? false
      accept [:applied_at]
      validate attribute_equals(:status, "pending")
      change set_attribute(:status, "applied")
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}

      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :proposed_change_apply}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :manual_intake_submit}
    end

    policy action(:set_payload) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :manual_intake_submit}
    end

    policy action(:reject) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :proposed_change_apply}
    end
  end
end
