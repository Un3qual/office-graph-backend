defmodule OfficeGraph.TestSupport.AshAuthorizationSupport do
  @moduledoc false

  require Ash.Query

  alias OfficeGraph.Content.Document
  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph
  alias OfficeGraph.WorkGraph.Artifact
  alias OfficeGraph.WorkGraph.EvidenceItem
  alias OfficeGraph.WorkGraph.GraphItem
  alias OfficeGraph.WorkGraph.GraphRelationship
  alias OfficeGraph.WorkGraph.ReviewFinding, as: ReviewFindingResource
  alias OfficeGraph.WorkGraph.Signal, as: SignalResource
  alias OfficeGraph.WorkGraph.Task, as: TaskResource
  alias OfficeGraph.WorkGraph.VerificationCheck, as: VerificationCheckResource
  alias OfficeGraph.WorkGraph.VerificationResult, as: VerificationResultResource

  defmacro __using__(_opts) do
    quote do
      use OfficeGraph.DataCase, async: false

      require Ash.Query

      alias OfficeGraph.Content.Document
      alias OfficeGraph.Authorization
      alias OfficeGraph.Authorization.AuthorizationDecision
      alias OfficeGraph.Foundation
      alias OfficeGraph.Operations
      alias OfficeGraph.QueryCounter
      alias OfficeGraph.Repo
      alias OfficeGraph.Verification
      alias OfficeGraph.WorkGraph
      alias OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences
      alias OfficeGraph.WorkGraph.Artifact
      alias OfficeGraph.WorkGraph.EvidenceItem
      alias OfficeGraph.WorkGraph.GraphItem
      alias OfficeGraph.WorkGraph.GraphRelationship
      alias OfficeGraph.WorkGraph.ReviewFinding, as: ReviewFindingResource
      alias OfficeGraph.WorkGraph.Signal, as: SignalResource
      alias OfficeGraph.WorkGraph.Task, as: TaskResource
      alias OfficeGraph.WorkGraph.VerificationCheck, as: VerificationCheckResource
      alias OfficeGraph.WorkGraph.VerificationResult.ValidateResultEvidence
      alias OfficeGraph.WorkGraph.VerificationResult, as: VerificationResultResource

      import OfficeGraph.TestSupport.AshAuthorizationSupport
    end
  end

  def bootstrap_scope(slug) do
    Foundation.bootstrap_local_owner(
      organization_name: "Office Graph #{slug}",
      organization_slug: "office-graph-#{slug}",
      workspace_name: "Workspace #{slug}",
      workspace_slug: "workspace-#{slug}",
      initiative_name: "Initiative #{slug}",
      initiative_slug: "initiative-#{slug}",
      owner_email: "owner-#{slug}@office-graph.local",
      owner_name: "Owner #{slug}"
    )
  end

  def create_limited_session_context!(bootstrap, purpose, capability_keys) do
    suffix = System.unique_integer([:positive])

    principal =
      Ash.create!(
        OfficeGraph.Identity.Principal,
        %{
          id: Ecto.UUID.generate(),
          email: "#{purpose}-#{suffix}@office-graph.local",
          kind: "human",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    session =
      Ash.create!(
        OfficeGraph.Identity.Session,
        %{
          id: Ecto.UUID.generate(),
          principal_id: principal.id,
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          purpose: purpose
        },
        action: :create,
        authorize?: false
      )

    role =
      Ash.create!(
        OfficeGraph.Authorization.Role,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          key: "#{purpose}-#{suffix}",
          name: purpose
        },
        action: :create,
        authorize?: false
      )

    Ash.create!(
      OfficeGraph.Authorization.RoleAssignment,
      %{
        id: Ecto.UUID.generate(),
        principal_id: principal.id,
        role_id: role.id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id
      },
      action: :create,
      authorize?: false
    )

    for key <- capability_keys do
      capability = ensure_capability!(key)

      Ash.create!(
        OfficeGraph.Authorization.RoleCapability,
        %{
          id: Ecto.UUID.generate(),
          role_id: role.id,
          capability_id: capability.id
        },
        action: :create,
        authorize?: false
      )
    end

    %OfficeGraph.Identity.SessionContext{
      principal_id: principal.id,
      session_id: session.id,
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      capabilities: MapSet.new(capability_keys)
    }
  end

  def ensure_capability!(key) do
    case Ash.get(OfficeGraph.Authorization.Capability, %{key: key},
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok, nil} ->
        Ash.create!(
          OfficeGraph.Authorization.Capability,
          %{
            id: Ecto.UUID.generate(),
            key: key,
            description: key
          },
          action: :create,
          authorize?: false
        )

      {:ok, capability} ->
        capability
    end
  end

  def create_signal!(bootstrap, title) do
    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{signal: signal}} =
      WorkGraph.create_signal(bootstrap.session, operation, %{
        title: title,
        body: "#{title} body"
      })

    signal
  end

  def create_verification_check!(bootstrap) do
    review_finding = create_review_finding!(bootstrap)
    create_verification_check!(bootstrap, review_finding)
  end

  def create_verification_check!(bootstrap, review_finding) do
    {:ok, graph_operation} =
      Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{verification_check: verification_check}} =
      WorkGraph.create_verification_check(
        bootstrap.session,
        graph_operation,
        review_finding,
        %{
          title: "Verification check",
          body: "Check body"
        }
      )

    verification_check
  end

  def create_review_finding!(bootstrap) do
    {:ok, signal_operation} =
      Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{signal: signal}} =
      WorkGraph.create_signal(bootstrap.session, signal_operation, %{
        title: "Verification source",
        body: "Source body"
      })

    task = create_task!(bootstrap, signal)
    create_review_finding!(bootstrap, task)
  end

  def create_task!(bootstrap, signal, title \\ "Verification task") do
    {:ok, graph_operation} =
      Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{task: task}} =
      WorkGraph.create_task(bootstrap.session, graph_operation, signal, %{
        title: title,
        body: "Task body"
      })

    task
  end

  def create_review_finding!(bootstrap, task) do
    {:ok, graph_operation} =
      Operations.start_operation(bootstrap.session, :proposed_change_apply)

    {:ok, %{review_finding: review_finding}} =
      WorkGraph.create_review_finding(bootstrap.session, graph_operation, task, %{
        title: "Verification finding",
        body: "Finding body"
      })

    review_finding
  end

  def create_verification_chain!(bootstrap) do
    signal = create_signal!(bootstrap, "Verification source")
    task = create_task!(bootstrap, signal)
    review_finding = create_review_finding!(bootstrap, task)
    verification_check = create_verification_check!(bootstrap, review_finding)

    OfficeGraph.TestSupport.VerificationGraph.build(
      signal,
      task,
      review_finding,
      verification_check
    )
  end

  def complete_verification!(bootstrap) do
    verification_check = create_verification_check!(bootstrap)
    {:ok, operation} = Operations.start_operation(bootstrap.session, :verification_complete)

    {:ok, completed} =
      Verification.complete_with_evidence(bootstrap.session, operation, verification_check, %{
        title: "Completed evidence",
        body: "Completed evidence body",
        artifact_uri: "https://example.test/completed-evidence"
      })

    completed
  end

  def relationship_exists?(source_item_id, target_item_id, relationship_type) do
    expected_source_id = source_item_id
    expected_target_id = target_item_id
    expected_type = relationship_type

    GraphRelationship
    |> Ash.Query.filter(
      source_item_id: expected_source_id,
      target_item_id: expected_target_id,
      relationship_type: expected_type
    )
    |> Ash.exists?(authorize?: false)
  end

  def bulk_signal_input(bootstrap, signal_id, graph_item_id, title) do
    document = insert_document!(bootstrap, "#{title} body")

    %{
      id: signal_id,
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      graph_item_id: graph_item_id,
      body_document_id: document.id,
      title: title
    }
  end

  def insert_graph_item!(bootstrap, resource_type, resource_id, title) do
    {:ok, graph_item} =
      Ash.create(
        GraphItem,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          resource_type: resource_type,
          resource_id: resource_id,
          title: title
        },
        action: :create,
        authorize?: false
      )

    graph_item
  end

  def insert_artifact!(bootstrap, title) do
    artifact_id = Ecto.UUID.generate()
    graph_item = insert_graph_item!(bootstrap, "artifact", artifact_id, "#{title} graph item")

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
      actor: bootstrap.session
    )
  end

  def insert_evidence_item!(bootstrap, verification_check, artifact) do
    evidence_id = Ecto.UUID.generate()

    graph_item =
      insert_graph_item!(
        bootstrap,
        "evidence_item",
        evidence_id,
        "Direct evidence graph item"
      )

    document = insert_document!(bootstrap, "Direct evidence body")

    Ash.create!(
      EvidenceItem,
      %{
        id: evidence_id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        graph_item_id: graph_item.id,
        verification_check_id: verification_check.id,
        artifact_id: artifact.id,
        body_document_id: document.id,
        title: "Direct evidence"
      },
      action: :create,
      actor: bootstrap.session
    )
  end

  def insert_document!(bootstrap, plain_text) do
    Ash.create!(
      Document,
      %{
        id: Ecto.UUID.generate(),
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        plain_text: plain_text
      },
      action: :create,
      authorize?: false
    )
  end

  def document_with_plain_text?(plain_text) do
    expected_plain_text = plain_text

    Document
    |> Ash.Query.filter(plain_text: expected_plain_text)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> false
      {:ok, _document} -> true
      {:error, _error} -> false
    end
  end

  def invalid_attribute_error?(errors, field, message_fragment) do
    Enum.any?(errors, fn
      %Ash.Error.Changes.InvalidAttribute{field: ^field, message: message} ->
        String.contains?(message, message_fragment)

      _error ->
        false
    end)
  end
end
