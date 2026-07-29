defmodule OfficeGraph.TestSupport.WorkPacketCommandLoopSupport.RunRequiredCheckRow do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.TestSupport.WorkPacketCommandLoopSupport.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "run_required_checks"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :run_id, :uuid, allow_nil?: false
    attribute :verification_check_id, :uuid, allow_nil?: false
  end

  actions do
    read :read do
      primary? true
    end

    destroy :destroy do
      primary? true
    end
  end
end

defmodule OfficeGraph.TestSupport.WorkPacketCommandLoopSupport.WorkPacketVersionRow do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.TestSupport.WorkPacketCommandLoopSupport.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "work_packet_versions"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false

    attribute :context_summary, :string,
      allow_nil?: false,
      constraints: [allow_empty?: true]

    attribute :requirements, :string,
      allow_nil?: false,
      constraints: [allow_empty?: true]
  end

  actions do
    read :read do
      primary? true
    end
  end
end

defmodule OfficeGraph.TestSupport.WorkPacketCommandLoopSupport.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource OfficeGraph.TestSupport.WorkPacketCommandLoopSupport.RunRequiredCheckRow
    resource OfficeGraph.TestSupport.WorkPacketCommandLoopSupport.WorkPacketVersionRow
  end
end

defmodule OfficeGraph.TestSupport.WorkPacketCommandLoopSupport do
  @moduledoc false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.Runs
  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.{Audit, Revisions}

  alias OfficeGraph.WorkGraph.{
    Artifact,
    EvidenceItem,
    EvidenceCandidate,
    GraphItem,
    GraphRelationship,
    ReviewFinding,
    Task,
    VerificationResult
  }

  alias OfficeGraph.WorkPackets

  alias OfficeGraph.WorkPackets.{
    WorkPacket,
    WorkPacketRequiredCheck,
    WorkPacketSourceReference,
    WorkPacketVersion
  }

  require Ash.Query

  defmacro __using__(_opts) do
    quote do
      use OfficeGraph.DataCase, async: false

      alias OfficeGraph.Foundation
      alias OfficeGraph.Operations
      alias OfficeGraph.QueryCounter
      alias OfficeGraph.Runs
      alias OfficeGraph.Authorization.AuthorizationDecision
      alias OfficeGraph.Runs.Changes.ValidateRunRequiredCheckContract
      alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
      alias OfficeGraph.Verification
      alias OfficeGraph.WorkGraph
      alias OfficeGraph.{Audit, Revisions}

      alias OfficeGraph.WorkGraph.{
        Artifact,
        EvidenceItem,
        EvidenceCandidate,
        GraphItem,
        GraphRelationship,
        ReviewFinding,
        Task,
        VerificationResult
      }

      alias OfficeGraph.WorkPackets

      alias OfficeGraph.WorkPackets.{
        WorkPacket,
        WorkPacketRequiredCheck,
        WorkPacketSourceReference,
        WorkPacketVersion
      }

      require Ash.Query

      import OfficeGraph.TestSupport.WorkPacketCommandLoopSupport
    end
  end

  def create_packet_with_operation(session, idempotency_key, attrs) do
    {:ok, operation} =
      Operations.start_operation(session, :work_packet_create, idempotency_key: idempotency_key)

    WorkPackets.create_packet(session, operation, attrs)
  end

  def start_waiver_command(session, key, run, required_check, attrs) do
    command_input =
      attrs
      |> Map.put(:run_id, run.id)
      |> Map.put(:run_required_check_id, required_check.id)

    Operations.start_command(session, :verification_waive, key, command_input)
  end

  def create_ready_run(session, verification_check) when not is_list(verification_check) do
    create_ready_run(session, [verification_check])
  end

  def create_ready_run(session, verification_checks) when is_list(verification_checks) do
    {:ok, packet_result} = create_ready_packet(session, verification_checks)
    {:ok, run_operation} = Operations.start_operation(session, :work_run_start)

    with {:ok, run_result} <-
           Runs.start_run(session, run_operation, packet_result.version, %{
             source_surface: "test",
             reason: "Execute ready packet.",
             authority_posture: "human_supervised"
           }) do
      {:ok,
       run_result
       |> Map.put(:packet, packet_result.packet)
       |> Map.put(:packet_version, packet_result.version)}
    end
  end

  def create_ready_packet(session, verification_checks) do
    {:ok, packet_operation} = Operations.start_operation(session, :work_packet_create)

    WorkPackets.create_packet(session, packet_operation, %{
      title: "Ready packet",
      objective: "Run selected work.",
      context_summary: "Ready context.",
      requirements: "Complete selected work.",
      success_criteria: "Required checks pass.",
      autonomy_posture: "human_supervised",
      source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
      verification_check_ids: Enum.map(verification_checks, & &1.id)
    })
  end

  def direct_run_attrs(session, packet_result, operation) do
    %{
      id: Ecto.UUID.generate(),
      organization_id: session.organization_id,
      workspace_id: session.workspace_id,
      work_packet_id: packet_result.packet.id,
      work_packet_version_id: packet_result.version.id,
      operation_id: operation.id,
      initiator_principal_id: session.principal_id,
      objective: packet_result.version.objective,
      authority_posture: "human_supervised",
      source_surface: "test",
      reason: "Direct run create validates the packet contract."
    }
  end

  def record_observation(session, run, verification_check, opts \\ []) do
    key = Keyword.get(opts, :key, Ecto.UUID.generate())
    normalized_status = Keyword.get(opts, :normalized_status, "succeeded")
    observed_status = Keyword.get(opts, :observed_status, "passed")
    freshness_state = Keyword.get(opts, :freshness_state, "fresh")
    trust_basis = Keyword.get(opts, :trust_basis, "owner_attested")

    {:ok, operation} =
      Operations.start_operation(session, :execution_observation_record,
        idempotency_key: "observation-operation:#{key}"
      )

    Runs.record_observation(session, operation, run, %{
      source_kind: "human",
      source_identity: "manual:#{key}",
      idempotency_key: "observation:#{key}",
      observed_status: observed_status,
      normalized_status: normalized_status,
      freshness_state: freshness_state,
      trust_basis: trust_basis,
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      rationale: "Human confirmed #{key}."
    })
  end

  def create_evidence_candidate(session, run, verification_check, observation, opts) do
    key = Keyword.get(opts, :key, Ecto.UUID.generate())

    {:ok, operation} =
      Operations.start_operation(session, :evidence_candidate_create,
        idempotency_key: "candidate-operation:#{key}"
      )

    Verification.create_evidence_candidate(session, operation, %{
      work_run_id: run.id,
      verification_check_id: verification_check.id,
      execution_observation_id: observation.id,
      artifact_id: Keyword.get(opts, :artifact_id),
      claim: "Evidence candidate #{key}.",
      source_kind: "human",
      source_identity: "manual:#{key}",
      freshness_state: Keyword.get(opts, :freshness_state, "fresh"),
      trust_basis: Keyword.get(opts, :trust_basis, "owner_attested"),
      sensitivity: "internal"
    })
  end

  def accept_candidate(session, candidate, opts) do
    key = Keyword.get(opts, :key, Ecto.UUID.generate())

    {:ok, operation} =
      Operations.start_operation(session, :evidence_accept,
        idempotency_key: "accept-operation:#{key}"
      )

    Verification.accept_evidence_candidate(session, operation, candidate, %{
      title: "Accepted evidence #{key}",
      body: "Accepted evidence body #{key}.",
      result: Keyword.get(opts, :result, "passed"),
      acceptance_policy_basis: "owner_acceptance"
    })
  end

  def create_required_verification_check(session) do
    with {:ok, graph} <- create_required_verification_graph(session) do
      {:ok, graph.verification_check}
    end
  end

  def create_required_verification_graph(session) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "Launch signal",
             body: "Launch signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "Launch task",
             body: "Launch task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "Launch finding",
             body: "Launch finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "Launch check",
             body: "Launch check body."
           }) do
      {:ok,
       OfficeGraph.TestSupport.VerificationGraph.build(
         signal,
         task,
         review_finding,
         verification_check
       )}
    end
  end

  def fetch_resource!(resource, id) do
    resource_id = id

    resource
    |> Ash.Query.filter(id: resource_id)
    |> Ash.read_one!(authorize?: false)
  end

  def relationship_exists?(source_item_id, target_item_id, relationship_type) do
    expected_source_id = source_item_id
    expected_target_id = target_item_id
    expected_type = relationship_type

    GraphRelationship
    |> Ash.Query.filter(
      source_item_id: expected_source_id,
      target_item_id: expected_target_id,
      lifecycle: "active"
    )
    |> Ash.Query.load(:definition)
    |> Ash.read!(authorize?: false)
    |> Enum.any?(&(&1.definition.key == expected_type))
  end

  def accepted_evidence_for_candidate?(candidate_id) do
    expected_candidate_id = candidate_id

    EvidenceItem
    |> Ash.Query.filter(candidate_id: expected_candidate_id)
    |> Ash.exists?(authorize?: false)
  end

  def run_for_operation?(operation_id) do
    expected_operation_id = operation_id

    Run
    |> Ash.Query.filter(operation_id: expected_operation_id)
    |> Ash.exists?(authorize?: false)
  end

  def verification_result_for_candidate_target?(candidate) do
    expected_check_id = candidate.verification_check_id
    expected_run_id = candidate.work_run_id

    VerificationResult
    |> Ash.Query.filter(
      verification_check_id: expected_check_id,
      work_run_id: expected_run_id
    )
    |> Ash.exists?(authorize?: false)
  end

  def insert_artifact!(bootstrap, title) do
    artifact_id = Ecto.UUID.generate()

    {:ok, graph_item} =
      Ash.create(
        GraphItem,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          resource_type: "artifact",
          resource_id: artifact_id,
          title: "#{title} graph item"
        },
        action: :create,
        authorize?: false
      )

    Ash.create!(
      Artifact,
      %{
        id: artifact_id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        graph_item_id: graph_item.id,
        title: title,
        uri: "https://example.test/#{artifact_id}"
      },
      action: :create,
      authorize?: false
    )
  end

  def insert_malformed_execution_observation!(session, operation, run, verification_check) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    Ash.Seed.seed!(ExecutionObservation, %{
      id: id,
      organization_id: session.organization_id,
      workspace_id: session.workspace_id,
      work_run_id: run.id,
      operation_id: operation.id,
      verification_check_id: verification_check.id,
      graph_item_id: verification_check.graph_item_id,
      source_kind: "human",
      source_identity: "manual:malformed-summary-observation",
      idempotency_key: "malformed-summary-observation",
      observed_status: "passed",
      normalized_status: "succeeded",
      ingested_at: now,
      freshness_state: "fresh",
      trust_basis: "owner_attested",
      rationale: "Malformed legacy row."
    })

    id
  end

  def delete_run_required_check!(run_id, verification_check_id) do
    __MODULE__.RunRequiredCheckRow
    |> Ash.Query.filter(run_id == ^run_id and verification_check_id == ^verification_check_id)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false))
  end

  def insert_non_packet_run!(session, work_packet_id) do
    run_id = Ecto.UUID.generate()

    Ash.Seed.seed!(Run, %{
      id: run_id,
      organization_id: session.organization_id,
      workspace_id: session.workspace_id,
      work_packet_id: work_packet_id,
      work_packet_version_id: nil,
      state: "running",
      aggregate_state: "running",
      execution_state: "pending",
      verification_state: "unverified"
    })

    run_id
  end

  def bootstrap_local_owner_for(suffix) do
    Foundation.bootstrap_local_owner(
      organization_name: "Organization #{suffix}",
      organization_slug: suffix,
      workspace_name: "Workspace #{suffix}",
      workspace_slug: "workspace-#{suffix}",
      initiative_name: "Initiative #{suffix}",
      initiative_slug: "initiative-#{suffix}",
      owner_email: "owner-#{suffix}@office-graph.local",
      owner_name: "Owner #{suffix}"
    )
  end

  def forge_packet_current_version!(packet_id, version_id) do
    WorkPacket
    |> Ash.get!(packet_id, authorize?: false)
    |> Ash.Seed.update!(%{current_version_id: version_id})
  end

  def blank_packet_execution_context!(version_id) do
    __MODULE__.WorkPacketVersionRow
    |> Ash.get!(version_id, authorize?: false)
    |> Ash.Seed.update!(%{context_summary: "", requirements: ""})
  end

  def run_exists_for_operation?(operation_id) do
    expected_operation_id = operation_id

    Run
    |> Ash.Query.filter(operation_id: expected_operation_id)
    |> Ash.exists?(authorize?: false)
  end
end
