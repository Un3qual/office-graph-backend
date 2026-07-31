defmodule OfficeGraph.Verification.Actions.CreateEvidenceCandidate do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraph.Verification.CommandResults.CreateEvidenceCandidate

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, attrs} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :evidence_candidate_create,
             idempotency_key,
             attrs
           ),
         {:ok, candidate} <-
           Verification.create_evidence_candidate(session_context, operation, attrs) do
      CreateEvidenceCandidate.from_result(operation, candidate)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end

defmodule OfficeGraph.Verification.Actions.AcceptEvidence do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.CommandSupport.CommandError
  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraph.Verification.CommandResults.AcceptEvidence

  @impl true
  def run(input, _opts, %{actor: session_context}) when is_map(session_context) do
    {idempotency_key, command_input} = Map.pop!(input.arguments, :idempotency_key)

    with {:ok, operation} <-
           Operations.start_command(
             session_context,
             :evidence_accept,
             idempotency_key,
             command_input
           ),
         {candidate_id, attrs} <- Map.pop!(command_input, :evidence_candidate_id),
         {:ok, candidate} <-
           Verification.get_candidate_for_accept_command(session_context, candidate_id),
         {:ok, result} <-
           Verification.accept_evidence_candidate(session_context, operation, candidate, attrs) do
      AcceptEvidence.from_result(operation, result)
    else
      {:error, error} -> {:error, CommandError.new(error)}
    end
  end

  def run(_input, _opts, _context), do: {:error, CommandError.new(:forbidden)}
end

defmodule OfficeGraph.Verification.CommandResults.CreateEvidenceCandidate do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :evidence_candidate, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkGraph.EvidenceCandidate]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :create_evidence_candidate_payload

  def from_result(operation, candidate) do
    new(
      command: "create_evidence_candidate",
      operation_id: operation.id,
      affected_ids: [TypedId.new!(type: "evidence_candidate", id: candidate.id)],
      evidence_candidate: candidate
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.Verification.CommandResults.CreateEvidenceCandidate do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        evidence_candidate: %{
          id: result.evidence_candidate.id,
          candidate_state: result.evidence_candidate.candidate_state
        }
      },
      options
    )
  end
end

defmodule OfficeGraph.Verification.CommandResults.AcceptEvidence do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :evidence_candidate, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkGraph.EvidenceCandidate]

    field :evidence_item, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkGraph.EvidenceItem]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :accept_evidence_payload

  def from_result(operation, result) do
    new(
      command: "accept_evidence",
      operation_id: operation.id,
      affected_ids: affected_ids(result),
      evidence_candidate: result.candidate,
      evidence_item: result.evidence_item
    )
  end

  defp affected_ids(result) do
    [
      TypedId.new!(type: "evidence_candidate", id: result.candidate.id),
      TypedId.new!(type: "evidence_item", id: result.evidence_item.id),
      TypedId.new!(type: "verification_result", id: result.verification_result.id)
    ] ++
      optional_typed_id("verification_check", result.affected_verification_check_id) ++
      optional_typed_id("run_required_check", result.affected_run_required_check_id) ++
      optional_typed_id("review_finding", result.affected_review_finding_id) ++
      optional_typed_id("task", result.affected_task_id) ++
      optional_typed_id("work_run", result.work_run)
  end

  defp optional_typed_id(_type, nil), do: []

  defp optional_typed_id(type, id) when is_binary(id),
    do: [TypedId.new!(type: type, id: id)]

  defp optional_typed_id(type, resource),
    do: [TypedId.new!(type: type, id: resource.id)]
end

defimpl Jason.Encoder, for: OfficeGraph.Verification.CommandResults.AcceptEvidence do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        evidence_candidate: %{
          id: result.evidence_candidate.id,
          candidate_state: result.evidence_candidate.candidate_state
        },
        evidence_item: %{id: result.evidence_item.id, state: result.evidence_item.state}
      },
      options
    )
  end
end

defmodule OfficeGraph.Verification.CandidateActionResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :reason, :term

    field :candidate, :struct, constraints: [instance_of: OfficeGraph.WorkGraph.EvidenceCandidate]

    field :evidence_item, :struct, constraints: [instance_of: OfficeGraph.WorkGraph.EvidenceItem]

    field :verification_result, :struct,
      constraints: [
        instance_of: Module.concat([OfficeGraph, WorkGraph, VerificationResult])
      ]

    field :evidence_graph_item, :struct,
      constraints: [instance_of: OfficeGraph.WorkGraph.GraphItem]

    field :work_run, :struct, constraints: [instance_of: Module.concat([OfficeGraph, Runs, Run])]
  end

  def candidate(candidate), do: new(status: "candidate", candidate: candidate)

  def accepted(result) do
    new(
      status: "accepted",
      candidate: result.candidate,
      evidence_item: result.evidence_item,
      verification_result: result.verification_result,
      evidence_graph_item: result.evidence_graph_item,
      work_run: result.work_run
    )
  end

  def rejected(reason), do: new(status: "rejected", reason: reason)

  def to_candidate_result(%__MODULE__{status: "candidate", candidate: candidate}),
    do: {:ok, candidate}

  def to_candidate_result(%__MODULE__{status: "rejected", reason: reason}),
    do: {:error, reason}

  def to_acceptance_result(%__MODULE__{status: "accepted"} = result) do
    {:ok,
     %{
       candidate: result.candidate,
       evidence_item: result.evidence_item,
       verification_result: result.verification_result,
       evidence_graph_item: result.evidence_graph_item,
       work_run: result.work_run
     }}
  end

  def to_acceptance_result(%__MODULE__{status: "rejected", reason: reason}),
    do: {:error, reason}
end

defmodule OfficeGraph.WorkGraph.EvidenceCandidate do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.WorkGraph.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "evidence_candidates"
    repo OfficeGraph.Repo

    identity_index_names(
      unique_agent_step: "evidence_candidates_agent_step_index",
      unique_operation: "evidence_candidates_operation_id_unique_index"
    )

    custom_indexes do
      index [:work_run_id, :inserted_at, :id],
        name: "evidence_candidates_work_run_inserted_at_id_index"
    end
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :step_key, :string, public?: true
    attribute :claim, :string, allow_nil?: false, public?: true
    attribute :source_kind, :string, allow_nil?: false, public?: true
    attribute :source_identity, :string, allow_nil?: false, public?: true
    attribute :freshness_state, :string, allow_nil?: false, public?: true
    attribute :trust_basis, :string, allow_nil?: false, public?: true
    attribute :sensitivity, :string, allow_nil?: false, public?: true
    attribute :candidate_state, :string, allow_nil?: false, public?: true
    attribute :rejection_reason, :string, allow_nil?: true, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :verification_check,
               Module.concat([OfficeGraph, WorkGraph, VerificationCheck]) do
      source_attribute :verification_check_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :artifact, OfficeGraph.WorkGraph.Artifact do
      source_attribute :artifact_id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :context_package, OfficeGraph.AgentRuntime.ContextPackage do
      source_attribute :context_package_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :execution, OfficeGraph.AgentRuntime.AgentExecution do
      source_attribute :execution_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :execution_observation, OfficeGraph.Runs.ExecutionObservation do
      source_attribute :execution_observation_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :work_run, Module.concat([OfficeGraph, Runs, Run]) do
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

    has_many :evidence_items, OfficeGraph.WorkGraph.EvidenceItem do
      source_attribute :id
      destination_attribute :candidate_id
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
    end

    read :read_for_accept_command do
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :organization_id,
        :workspace_id,
        :verification_check_id,
        :work_run_id,
        :execution_observation_id,
        :artifact_id,
        :operation_id,
        :execution_id,
        :context_package_id,
        :step_key,
        :claim,
        :source_kind,
        :source_identity,
        :freshness_state,
        :trust_basis,
        :sensitivity
      ]

      change set_attribute(:candidate_state, "candidate")
      change set_attribute(:rejection_reason, nil)

      change {OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences,
              references: [
                verification_check_id: Module.concat([OfficeGraph, WorkGraph, VerificationCheck]),
                artifact_id: OfficeGraph.WorkGraph.Artifact,
                operation_id: OfficeGraph.Operations.OperationCorrelation
              ]}

      change OfficeGraph.WorkGraph.Changes.ValidateEvidenceCandidateReferences
    end

    update :mark_accepted do
      public? false
      accept []
      change set_attribute(:candidate_state, "accepted")
    end

    action :persist_candidate_contract, OfficeGraph.Verification.CandidateActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Runs.ExecutionObservation,
        Module.concat([OfficeGraph, Runs, Run]),
        OfficeGraph.Runs.RunRequiredCheck,
        OfficeGraph.WorkGraph.Artifact,
        Module.concat([OfficeGraph, WorkGraph, VerificationCheck])
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :verification_check_id, :uuid, allow_nil?: false
      argument :work_run_id, :uuid
      argument :execution_observation_id, :uuid
      argument :artifact_id, :uuid
      argument :claim, :string, allow_nil?: false
      argument :source_kind, :string, allow_nil?: false
      argument :source_identity, :string, allow_nil?: false
      argument :freshness_state, :string, allow_nil?: false
      argument :trust_basis, :string, allow_nil?: false
      argument :sensitivity, :string, allow_nil?: false

      run {Module.concat([OfficeGraph, Verification]), mode: :create_candidate}
    end

    action :accept_candidate_contract, OfficeGraph.Verification.CandidateActionResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Audit.AuditRecord,
        OfficeGraph.Content.Document,
        OfficeGraph.Content.DocumentBlock,
        OfficeGraph.Content.DocumentRevision,
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Revisions.Revision,
        OfficeGraph.Runs.ExecutionObservation,
        Module.concat([OfficeGraph, Runs, Run]),
        OfficeGraph.Runs.RunRequiredCheck,
        OfficeGraph.WorkGraph.Artifact,
        OfficeGraph.WorkGraph.EvidenceItem,
        OfficeGraph.WorkGraph.GraphItem,
        Module.concat([OfficeGraph, WorkGraph, GraphRelationship]),
        OfficeGraph.WorkGraph.RelationshipDefinition,
        OfficeGraph.WorkGraph.RelationshipEndpointRule,
        Module.concat([OfficeGraph, WorkGraph, ReviewFinding]),
        Module.concat([OfficeGraph, WorkGraph, Task]),
        Module.concat([OfficeGraph, WorkGraph, VerificationCheck]),
        Module.concat([OfficeGraph, WorkGraph, VerificationResult])
      ]

      argument :operation_id, :uuid, allow_nil?: false
      argument :candidate_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false
      argument :body, :string, default: ""
      argument :result, :string, default: "passed"
      argument :acceptance_policy_basis, :string
      argument :reason, :string

      run {Module.concat([OfficeGraph, Verification]), mode: :accept_candidate}
    end

    action :create_evidence_candidate,
           OfficeGraph.Verification.CommandResults.CreateEvidenceCandidate do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :work_run_id, :uuid, allow_nil?: false
      argument :verification_check_id, :uuid, allow_nil?: false
      argument :execution_observation_id, :uuid, allow_nil?: false
      argument :claim, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :source_kind, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :source_identity, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :freshness_state, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :trust_basis, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :sensitivity, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      run OfficeGraph.Verification.Actions.CreateEvidenceCandidate
    end

    action :accept_evidence, OfficeGraph.Verification.CommandResults.AcceptEvidence do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :evidence_candidate_id, :uuid, allow_nil?: false
      argument :title, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      argument :body, :string,
        allow_nil?: false,
        constraints: [trim?: false, match: ~r/\S/]

      argument :result, :string, allow_nil?: false, constraints: [match: ~r/\S/]

      argument :acceptance_policy_basis, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      run OfficeGraph.Verification.Actions.AcceptEvidence
    end
  end

  identities do
    identity :unique_agent_step, [:execution_id, :step_key]

    identity :unique_operation, [:operation_id]
  end

  policies do
    policy action(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action(:read_for_accept_command) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :evidence_accept}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end

    policy action(:create) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :evidence_candidate_create}
    end

    policy action(:create_evidence_candidate) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :evidence_candidate_create}
    end

    policy action(:accept_evidence) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :evidence_accept}
    end
  end

  graphql do
    type :evidence_candidate
  end

  json_api do
    type "evidence_candidate"
  end
end
