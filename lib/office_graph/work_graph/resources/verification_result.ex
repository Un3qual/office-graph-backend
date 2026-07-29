defmodule OfficeGraph.Verification.Actions.WaiveVerificationCheck do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraph.Verification.CommandResults.WaiveVerificationCheck

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :verification_waive,
             idempotency_key,
             command_input
           ),
         {run_id, command_input} <- Map.pop!(command_input, :run_id),
         {required_check_id, attrs} <- Map.pop!(command_input, :run_required_check_id),
         {:ok, run} <- Verification.get_run_for_waive_command(session_context, run_id),
         {:ok, required_check} <-
           Verification.get_required_check_for_waive_command(
             session_context,
             required_check_id
           ),
         {:ok, result} <-
           Verification.waive_required_check(
             session_context,
             operation,
             run,
             required_check,
             attrs
           ) do
      WaiveVerificationCheck.from_result(operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end

defmodule OfficeGraph.Verification.CommandResults.WaiveVerificationCheck do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :verification_result, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkGraph.VerificationResult]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :waive_verification_check_payload

  def from_result(operation, result) do
    new(
      command: "waive_verification_check",
      operation_id: operation.id,
      affected_ids: [
        TypedId.new!(type: "verification_result", id: result.verification_result.id),
        TypedId.new!(type: "run_required_check", id: result.required_check.id),
        TypedId.new!(type: "work_run", id: result.run.id)
      ],
      verification_result: result.verification_result
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.Verification.CommandResults.WaiveVerificationCheck do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        verification_result: %{
          id: result.verification_result.id,
          result: result.verification_result.result
        }
      },
      options
    )
  end
end

defmodule OfficeGraph.Verification.WaiverActionResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :reason, :term

    field :verification_result, :struct,
      constraints: [instance_of: OfficeGraph.WorkGraph.VerificationResult]

    field :required_check, :struct, constraints: [instance_of: OfficeGraph.Runs.RunRequiredCheck]

    field :run, :struct, constraints: [instance_of: OfficeGraph.Runs.Run]
  end

  def waived(result) do
    new(
      status: "waived",
      verification_result: result.verification_result,
      required_check: result.required_check,
      run: result.run
    )
  end

  def rejected(reason), do: new(status: "rejected", reason: reason)

  def to_public_result(%__MODULE__{status: "waived"} = result) do
    {:ok,
     %{
       verification_result: result.verification_result,
       required_check: result.required_check,
       run: result.run
     }}
  end

  def to_public_result(%__MODULE__{status: "rejected", reason: reason}),
    do: {:error, reason}
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
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :policy_basis, :string, allow_nil?: true, public?: true
    attribute :reason, :string, allow_nil?: true, public?: true
    attribute :recorded_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :result, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :verification_check, OfficeGraph.WorkGraph.VerificationCheck do
      source_attribute :verification_check_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :evidence_item, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :evidence_item_id
      allow_nil? true
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :target_graph_item, OfficeGraph.WorkGraph.GraphItem do
      source_attribute :target_graph_item_id
      attribute_public? true
    end

    belongs_to :actor_principal, OfficeGraph.Identity.Principal do
      source_attribute :actor_principal_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :work_packet_version, OfficeGraph.WorkPackets.WorkPacketVersion do
      source_attribute :work_packet_version_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :work_run, OfficeGraph.Runs.Run do
      source_attribute :work_run_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
    end

    create :create do
      public? false

      accept [
        :id,
        :organization_id,
        :workspace_id,
        :verification_check_id,
        :evidence_item_id,
        :operation_id,
        :work_run_id,
        :work_packet_version_id,
        :target_graph_item_id,
        :actor_principal_id,
        :policy_basis,
        :reason,
        :recorded_at,
        :result
      ]

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
                evidence_item_id: OfficeGraph.WorkGraph.EvidenceItem,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}

      change OfficeGraph.WorkGraph.VerificationResult.ValidateResultEvidence
    end

    action :persist_waiver_contract, OfficeGraph.Verification.WaiverActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        OfficeGraph.Runs.Run,
        OfficeGraph.Runs.RunRequiredCheck,
        OfficeGraph.WorkGraph.VerificationCheck
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :run_id, :uuid, allow_nil?: false
      argument :required_check_id, :uuid, allow_nil?: false
      argument :expected_execution_state, :string, allow_nil?: false
      argument :expected_verification_state, :string, allow_nil?: false
      argument :reason, :string, allow_nil?: false
      argument :policy_basis, :string, allow_nil?: false

      run {OfficeGraph.Verification.Waiver, mode: :persist_waiver}
    end

    action :waive_verification_check,
           OfficeGraph.Verification.CommandResults.WaiveVerificationCheck do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :run_id, :uuid, allow_nil?: false
      argument :run_required_check_id, :uuid, allow_nil?: false

      argument :expected_execution_state, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :expected_verification_state, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :reason, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :policy_basis, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      run OfficeGraph.Verification.Actions.WaiveVerificationCheck
    end
  end

  policies do
    policy action(:waive_verification_check) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :verification_waive}
    end

    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end
  end

  graphql do
    type :work_graph_verification_result
  end

  json_api do
    type "verification_result"
  end
end
