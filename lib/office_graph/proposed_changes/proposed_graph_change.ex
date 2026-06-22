defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.TraceReferenceScope do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.Integrations.NormalizedIntakeEvent
  alias OfficeGraph.Operations.OperationCorrelation

  require Ash.Query

  @manual_intake_action "manual_intake.submit"

  @trace_references [
    operation_id: OperationCorrelation,
    normalized_event_id: NormalizedIntakeEvent
  ]

  @impl true
  def change(changeset, _opts, context) do
    actor = Map.get(context, :actor)

    with {:ok, organization_id, workspace_id} <- target_scope(changeset) do
      @trace_references
      |> Enum.reduce(changeset, fn {field, resource}, changeset ->
        validate_reference(changeset, field, resource, organization_id, workspace_id, actor)
      end)
      |> validate_normalized_event_operation()
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

  defp validate_reference(
         changeset,
         :operation_id = field,
         OperationCorrelation = resource,
         organization_id,
         workspace_id,
         actor
       ) do
    case Ash.Changeset.get_attribute(changeset, field) do
      nil ->
        changeset

      id ->
        case fetch_reference(resource, id) do
          {:ok,
           %{
             organization_id: ^organization_id,
             workspace_id: ^workspace_id,
             principal_id: principal_id,
             session_id: session_id,
             action: @manual_intake_action
           }} ->
            if same_actor?(actor, principal_id, session_id) do
              changeset
            else
              add_operation_context_error(changeset)
            end

          {:ok, %{organization_id: ^organization_id, workspace_id: ^workspace_id}} ->
            add_operation_context_error(changeset)

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

  defp validate_reference(changeset, field, resource, organization_id, workspace_id, _actor) do
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

  defp validate_normalized_event_operation(%{valid?: false} = changeset), do: changeset

  defp validate_normalized_event_operation(changeset) do
    operation_id = Ash.Changeset.get_attribute(changeset, :operation_id)
    normalized_event_id = Ash.Changeset.get_attribute(changeset, :normalized_event_id)

    if is_nil(operation_id) or is_nil(normalized_event_id) do
      changeset
    else
      validate_normalized_event_operation(changeset, operation_id, normalized_event_id)
    end
  end

  defp validate_normalized_event_operation(changeset, operation_id, normalized_event_id) do
    case fetch_reference(NormalizedIntakeEvent, normalized_event_id) do
      {:ok, %{operation_id: ^operation_id}} ->
        changeset

      {:ok, _event} ->
        add_event_operation_error(changeset)

      {:error, error} ->
        Ash.Changeset.add_error(
          changeset,
          field: :normalized_event_id,
          message: "normalized_event_id lookup failed: #{format_lookup_error(error)}"
        )
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

  defp add_operation_context_error(changeset) do
    Ash.Changeset.add_error(
      changeset,
      field: :operation_id,
      message: "operation_id must reference the current manual intake operation"
    )
  end

  defp add_event_operation_error(changeset) do
    Ash.Changeset.add_error(
      changeset,
      field: :normalized_event_id,
      message: "normalized_event_id must reference an event produced by operation_id"
    )
  end

  defp same_actor?(actor, principal_id, session_id) when is_map(actor) do
    actor.principal_id == principal_id and actor.session_id == session_id
  end

  defp same_actor?(_actor, _principal_id, _session_id), do: false

  defp format_lookup_error(%{__exception__: true} = error), do: Exception.message(error)
  defp format_lookup_error(error), do: inspect(error)
end

defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.ValidateUniqueNormalizedEventChangeType do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.ProposedChanges.ProposedGraphChange

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    normalized_event_id = Ash.Changeset.get_attribute(changeset, :normalized_event_id)
    change_type = Ash.Changeset.get_attribute(changeset, :change_type)

    if is_nil(normalized_event_id) or is_nil(change_type) do
      changeset
    else
      validate_unique_event_change_type(changeset, normalized_event_id, change_type)
    end
  end

  defp validate_unique_event_change_type(changeset, normalized_event_id, change_type) do
    ProposedGraphChange
    |> Ash.Query.filter(
      normalized_event_id == ^normalized_event_id and change_type == ^change_type
    )
    |> Ash.exists?(authorize?: false)
    |> case do
      true ->
        changeset
        |> Ash.Changeset.add_error(
          field: :normalized_event_id,
          message: "normalized_event_id and change_type must be unique"
        )
        |> Ash.Changeset.add_error(
          field: :change_type,
          message: "normalized_event_id and change_type must be unique"
        )

      false ->
        changeset
    end
  end
end

defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.ValidatePendingUpdate do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.ProposedChanges.ProposedGraphChange

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case changeset.data do
        %{id: id} when is_binary(id) ->
          validate_current_status(changeset, id)

        _data ->
          changeset
      end
    end)
  end

  defp validate_current_status(changeset, id) do
    ProposedGraphChange
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %{status: "pending"}} ->
        changeset

      {:ok, _non_pending_or_missing} ->
        Ash.Changeset.add_error(changeset,
          field: :status,
          message: "must be pending"
        )

      {:error, error} ->
        Ash.Changeset.add_error(changeset,
          field: :status,
          message: "status lookup failed: #{inspect(error)}"
        )
    end
  end
end

defmodule OfficeGraph.ProposedChanges.ProposedGraphChange.OriginatingOperationActor do
  @moduledoc false

  use Ash.Policy.SimpleCheck

  alias OfficeGraph.Operations.OperationCorrelation

  @impl true
  def describe(opts) do
    "actor owns proposed change operation #{inspect(opts[:action])}"
  end

  @impl true
  def match?(actor, context, opts) do
    expected_action = opts[:action]

    with true <- is_map(actor),
         {:ok, operation_id, organization_id, workspace_id} <- proposed_change_context(context),
         {:ok, operation} <- fetch_operation(operation_id),
         true <- operation.action == expected_action,
         true <- operation.principal_id == actor.principal_id,
         true <- operation.session_id == actor.session_id,
         true <- operation.organization_id == organization_id,
         true <- operation.workspace_id == workspace_id,
         true <- actor.organization_id == organization_id,
         true <- actor.workspace_id == workspace_id do
      true
    else
      _ -> false
    end
  end

  defp proposed_change_context(context) when is_map(context) do
    context
    |> subject()
    |> case do
      %Ash.Changeset{} = changeset ->
        operation_id = read_value(changeset, :operation_id)
        organization_id = read_value(changeset, :organization_id)
        workspace_id = read_value(changeset, :workspace_id)

        if operation_id && organization_id && workspace_id do
          {:ok, operation_id, organization_id, workspace_id}
        else
          :error
        end

      _subject ->
        :error
    end
  end

  defp proposed_change_context(_context), do: :error

  defp subject(context) do
    Map.get(context, :subject) || Map.get(context, :changeset)
  end

  defp read_value(%Ash.Changeset{} = changeset, field) do
    Map.get(changeset.attributes, field) || scope_value(changeset.data, field)
  end

  defp scope_value(data, field) when is_map(data), do: Map.get(data, field)
  defp scope_value(_data, _field), do: nil

  defp fetch_operation(operation_id) do
    OperationCorrelation
    |> Ash.get(operation_id, authorize?: false, not_found_error?: false)
    |> case do
      {:ok, nil} -> :error
      {:ok, operation} -> {:ok, operation}
      {:error, _error} -> :error
    end
  end
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

    identity_index_names unique_normalized_event_change_type:
                           "proposed_graph_changes_event_type_index"

    foreign_key_names organization_id: "proposed_graph_changes_organization_id_fkey",
                      workspace_id: "proposed_graph_changes_workspace_id_fkey",
                      operation_id: "proposed_graph_changes_operation_id_fkey",
                      applied_operation_id: "proposed_graph_changes_applied_operation_id_fkey",
                      normalized_event_id: "proposed_graph_changes_normalized_event_id_fkey"
  end

  identities do
    identity :unique_normalized_event_change_type, [:normalized_event_id, :change_type],
      where: expr(not is_nil(normalized_event_id))
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :operation_id, :uuid, allow_nil?: false, public?: true
    attribute :applied_operation_id, :uuid, public?: true
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

      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidateUniqueNormalizedEventChangeType
    end

    update :set_payload do
      require_atomic? false
      accept [:payload]
      validate attribute_equals(:status, "pending")
      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidatePendingUpdate
    end

    update :reject do
      require_atomic? false
      accept [:validation_errors]
      validate attribute_equals(:status, "pending")
      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidatePendingUpdate
      change set_attribute(:status, "rejected")
    end

    update :mark_applied do
      require_atomic? false
      accept [:applied_at, :applied_operation_id]
      validate attribute_equals(:status, "pending")
      change OfficeGraph.ProposedChanges.ProposedGraphChange.ValidatePendingUpdate
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
      forbid_unless {OfficeGraph.ProposedChanges.ProposedGraphChange.OriginatingOperationActor,
                     action: "manual_intake.submit"}

      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :manual_intake_submit}
    end

    policy action(:reject) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :proposed_change_apply}
    end

    policy action(:mark_applied) do
      forbid_if always()
    end
  end
end
