defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Resource do
  @moduledoc false

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    id_type = Keyword.get(opts, :id_type, :uuid)
    clear_attributes = Keyword.get(opts, :clear_attributes, [])

    attributes =
      for {name, type} <- Keyword.get(opts, :attributes, []) do
        quote do
          attribute unquote(name), unquote(type), allow_nil?: true, public?: false
        end
      end

    clear_actions =
      if clear_attributes == [] do
        []
      else
        clear_changes =
          for attribute <- clear_attributes do
            quote do
              change set_attribute(unquote(attribute), nil)
            end
          end

        [
          quote do
            update :clear_references do
              (unquote_splicing(clear_changes))
            end
          end
        ]
      end

    quote do
      use Ash.Resource,
        domain: OfficeGraph.TestSupport.ConcurrencyCleanup.Domain,
        data_layer: AshPostgres.DataLayer

      postgres do
        table unquote(table)
        repo OfficeGraph.Repo
        migrate? false
      end

      attributes do
        attribute :id, unquote(id_type),
          primary_key?: true,
          allow_nil?: false,
          public?: false

        unquote_splicing(attributes)
      end

      actions do
        read :read do
          primary? true
          public? false
        end

        destroy :destroy do
          primary? true
          public? false
        end

        unquote_splicing(clear_actions)
      end
    end
  end
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Artifact do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "artifacts",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.AuditRecord do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "audit_records",
    attributes: [operation_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.AuthenticationEvent do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "authentication_events",
    attributes: [organization_id: :uuid, principal_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.AuthorizationDecision do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "authorization_decisions",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Conversation do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "conversations",
    attributes: [organization_id: :uuid, run_id: :uuid, graph_item_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.ConversationMessage do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "conversation_messages",
    attributes: [conversation_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Document do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "documents",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.DocumentBlock do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "document_blocks",
    attributes: [document_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.DocumentMark do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "document_marks",
    attributes: [block_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.DocumentReference do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "document_references",
    attributes: [document_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.DocumentRevision do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "document_revisions",
    attributes: [document_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.DomainEvent do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "domain_events",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.EvidenceCandidate do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "evidence_candidates",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.EvidenceItem do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "evidence_items",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.ExecutionObservation do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "execution_observations",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.ExternalIdentityLink do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "external_identity_links",
    attributes: [principal_id: :uuid, verified_email: :string]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.ExternalSource do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "external_sources",
    attributes: [key: :string]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.GraphItem do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "graph_items",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.GraphRelationship do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "graph_relationships",
    attributes: [source_item_id: :uuid, target_item_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Initiative do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "initiatives",
    attributes: [organization_id: :uuid, slug: :string]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Job do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "oban_jobs",
    id_type: :integer,
    attributes: [args: :map]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.NormalizedIntakeEvent do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "normalized_intake_events",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.OperationCorrelation do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "operation_correlations",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Organization do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "organizations",
    attributes: [slug: :string]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.PolicyBundle do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "policy_bundles",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Principal do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "principals",
    attributes: [email: :string]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.PrincipalProfile do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "principal_profiles",
    attributes: [principal_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.ProposedGraphChange do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "proposed_graph_changes",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.RawArchive do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "raw_archives",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.ReviewFinding do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "review_findings",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Revision do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "revisions",
    attributes: [operation_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Role do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "roles",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.RoleAssignment do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "role_assignments",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.RoleCapability do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "role_capabilities",
    attributes: [role_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Run do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "runs",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.RunRequiredCheck do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "run_required_checks",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Session do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "sessions",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Signal do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "signals",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Task do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "tasks",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.VerificationCheck do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "verification_checks",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.VerificationResult do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "verification_results",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.WorkPacket do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "work_packets",
    attributes: [organization_id: :uuid, current_version_id: :uuid],
    clear_attributes: [:current_version_id]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.WorkPacketVersion do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "work_packet_versions",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.WorkPacketVersionRequiredCheck do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "work_packet_version_required_checks",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.WorkPacketVersionSource do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "work_packet_version_sources",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Workspace do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "workspaces",
    attributes: [organization_id: :uuid, slug: :string]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Workstream do
  use OfficeGraph.TestSupport.ConcurrencyCleanup.Resource,
    table: "workstreams",
    attributes: [organization_id: :uuid, slug: :string]
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Artifact
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.AuditRecord
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.AuthenticationEvent
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.AuthorizationDecision
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Conversation
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.ConversationMessage
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Document
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.DocumentBlock
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.DocumentMark
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.DocumentReference
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.DocumentRevision
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.DomainEvent
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.EvidenceCandidate
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.EvidenceItem
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.ExecutionObservation
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.ExternalIdentityLink
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.ExternalSource
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.GraphItem
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.GraphRelationship
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Initiative
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Job
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.NormalizedIntakeEvent
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.OperationCorrelation
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Organization
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.PolicyBundle
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Principal
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.PrincipalProfile
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.ProposedGraphChange
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.RawArchive
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.ReviewFinding
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Revision
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Role
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.RoleAssignment
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.RoleCapability
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Run
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.RunRequiredCheck
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Session
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Signal
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Task
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.VerificationCheck
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.VerificationResult
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.WorkPacket
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.WorkPacketVersion
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.WorkPacketVersionRequiredCheck
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.WorkPacketVersionSource
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Workspace
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Workstream
  end
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup do
  @moduledoc false

  alias __MODULE__.{
    Artifact,
    AuditRecord,
    AuthenticationEvent,
    AuthorizationDecision,
    Conversation,
    ConversationMessage,
    Document,
    DocumentBlock,
    DocumentMark,
    DocumentReference,
    DocumentRevision,
    DomainEvent,
    EvidenceCandidate,
    EvidenceItem,
    ExecutionObservation,
    ExternalIdentityLink,
    ExternalSource,
    GraphItem,
    GraphRelationship,
    Initiative,
    Job,
    NormalizedIntakeEvent,
    OperationCorrelation,
    Organization,
    PolicyBundle,
    Principal,
    PrincipalProfile,
    ProposedGraphChange,
    RawArchive,
    ReviewFinding,
    Revision,
    Role,
    RoleAssignment,
    RoleCapability,
    Run,
    RunRequiredCheck,
    Session,
    Signal,
    Task,
    VerificationCheck,
    VerificationResult,
    WorkPacket,
    WorkPacketVersion,
    WorkPacketVersionRequiredCheck,
    WorkPacketVersionSource,
    Workspace,
    Workstream
  }

  require Ash.Query

  def conversation_count(run_id, graph_item_id) do
    Conversation
    |> Ash.Query.filter(run_id == ^run_id and graph_item_id == ^graph_item_id)
    |> count!()
  end

  def cleanup_conversation_scope!(organization_slug) do
    organization_ids = organization_ids(organization_slug)

    conversation_ids =
      Conversation
      |> Ash.Query.filter(organization_id in ^organization_ids)
      |> ids!()

    ConversationMessage
    |> Ash.Query.filter(conversation_id in ^conversation_ids)
    |> destroy_all!()

    Conversation
    |> Ash.Query.filter(organization_id in ^organization_ids)
    |> destroy_all!()
  end

  def cleanup_owner_principal!(owner_email) do
    principal_ids =
      Principal
      |> Ash.Query.filter(email == ^owner_email)
      |> ids!()

    PrincipalProfile
    |> Ash.Query.filter(principal_id in ^principal_ids)
    |> destroy_all!()

    ExternalIdentityLink
    |> Ash.Query.filter(principal_id in ^principal_ids or verified_email == ^owner_email)
    |> destroy_all!()

    Principal
    |> Ash.Query.filter(id in ^principal_ids)
    |> destroy_all!()
  end

  def cleanup_committed_scope!(organization_id, principal_ids, source_identities) do
    cleanup_work_run_verification_scope_by_id!(organization_id)
    cleanup_jobs!(organization_id)
    destroy_for_organization!(DomainEvent, organization_id)
    destroy_for_organization!(ProposedGraphChange, organization_id)
    destroy_for_organization!(NormalizedIntakeEvent, organization_id)
    destroy_for_organization!(RawArchive, organization_id)
    source_identities = List.wrap(source_identities)

    ExternalSource
    |> Ash.Query.filter(key in ^source_identities)
    |> destroy_all!()

    destroy_for_organization!(AuthorizationDecision, organization_id)
    destroy_for_organization!(OperationCorrelation, organization_id)

    role_ids =
      Role
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> ids!()

    RoleCapability
    |> Ash.Query.filter(role_id in ^role_ids)
    |> destroy_all!()

    destroy_for_organization!(RoleAssignment, organization_id)
    destroy_for_organization!(Role, organization_id)
    destroy_for_organization!(Session, organization_id)
    destroy_for_organization!(Workspace, organization_id)

    principal_ids = List.wrap(principal_ids)

    Principal
    |> Ash.Query.filter(id in ^principal_ids)
    |> destroy_all!()

    Organization
    |> Ash.Query.filter(id == ^organization_id)
    |> destroy_all!()
  end

  def cleanup_work_run_verification_scope!(organization_slug) do
    Enum.each(organization_ids(organization_slug), fn organization_id ->
      cleanup_work_run_verification_scope_by_id!(organization_id)
      cleanup_jobs!(organization_id)
      destroy_for_organization!(DomainEvent, organization_id)
      destroy_for_organization!(ProposedGraphChange, organization_id)
      destroy_for_organization!(NormalizedIntakeEvent, organization_id)
      destroy_for_organization!(RawArchive, organization_id)
      destroy_for_organization!(AuthorizationDecision, organization_id)
      destroy_for_organization!(OperationCorrelation, organization_id)
    end)
  end

  def cleanup_work_run_verification_scope_by_id!(organization_id) do
    destroy_for_organization!(VerificationResult, organization_id)
    destroy_for_organization!(EvidenceItem, organization_id)
    destroy_for_organization!(EvidenceCandidate, organization_id)
    destroy_for_organization!(ExecutionObservation, organization_id)
    destroy_for_organization!(RunRequiredCheck, organization_id)
    destroy_for_organization!(Run, organization_id)
    destroy_for_organization!(WorkPacketVersionRequiredCheck, organization_id)
    destroy_for_organization!(WorkPacketVersionSource, organization_id)
    clear_work_packet_current_versions!(organization_id)
    destroy_for_organization!(WorkPacketVersion, organization_id)
    destroy_for_organization!(WorkPacket, organization_id)
    destroy_for_organization!(Artifact, organization_id)
    destroy_for_organization!(VerificationCheck, organization_id)
    destroy_for_organization!(ReviewFinding, organization_id)
    destroy_for_organization!(Task, organization_id)
    destroy_for_organization!(Signal, organization_id)

    graph_item_ids =
      GraphItem
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> ids!()

    GraphRelationship
    |> Ash.Query.filter(source_item_id in ^graph_item_ids or target_item_id in ^graph_item_ids)
    |> destroy_all!()

    destroy_for_organization!(GraphItem, organization_id)
    cleanup_documents!(organization_id)

    operation_ids =
      OperationCorrelation
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> ids!()

    AuditRecord
    |> Ash.Query.filter(operation_id in ^operation_ids)
    |> destroy_all!()

    Revision
    |> Ash.Query.filter(operation_id in ^operation_ids)
    |> destroy_all!()
  end

  def tenancy_scope_counts(organization_slug, workspace_slug, initiative_slug) do
    organization_ids = organization_ids(organization_slug)

    organization_count = length(organization_ids)

    workspace_count =
      Workspace
      |> Ash.Query.filter(organization_id in ^organization_ids and slug == ^workspace_slug)
      |> count!()

    initiative_count =
      Initiative
      |> Ash.Query.filter(organization_id in ^organization_ids and slug == ^initiative_slug)
      |> count!()

    workstream_count =
      Workstream
      |> Ash.Query.filter(organization_id in ^organization_ids and slug == "default")
      |> count!()

    {organization_count, workspace_count, initiative_count, workstream_count}
  end

  def cleanup_tenancy_scope!(organization_slug) do
    organization_ids = organization_ids(organization_slug)

    role_ids =
      Role
      |> Ash.Query.filter(organization_id in ^organization_ids)
      |> ids!()

    RoleCapability
    |> Ash.Query.filter(role_id in ^role_ids)
    |> destroy_all!()

    AuthenticationEvent
    |> Ash.Query.filter(organization_id in ^organization_ids)
    |> destroy_all!()

    for resource <- [
          RoleAssignment,
          PolicyBundle,
          Role,
          Session,
          Workstream,
          Initiative,
          Workspace
        ] do
      resource
      |> Ash.Query.filter(organization_id in ^organization_ids)
      |> destroy_all!()
    end

    Organization
    |> Ash.Query.filter(id in ^organization_ids)
    |> destroy_all!()
  end

  defp cleanup_jobs!(organization_id) do
    Job
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(get_in(&1.args, ["organization_id"]) == organization_id))
    |> Enum.each(&Ash.destroy!(&1, authorize?: false))
  end

  defp organization_ids(slug) do
    Organization
    |> Ash.Query.filter(slug == ^slug)
    |> ids!()
  end

  defp destroy_for_organization!(resource, organization_id) do
    resource
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> destroy_all!()
  end

  defp clear_work_packet_current_versions!(organization_id) do
    WorkPacket
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> Ash.bulk_update!(:clear_references, %{},
      authorize?: false,
      return_errors?: true,
      strategy: [:atomic]
    )

    :ok
  end

  defp cleanup_documents!(organization_id) do
    document_ids =
      Document
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> ids!()

    block_ids =
      DocumentBlock
      |> Ash.Query.filter(document_id in ^document_ids)
      |> ids!()

    DocumentMark
    |> Ash.Query.filter(block_id in ^block_ids)
    |> destroy_all!()

    for resource <- [DocumentReference, DocumentRevision, DocumentBlock] do
      resource
      |> Ash.Query.filter(document_id in ^document_ids)
      |> destroy_all!()
    end

    Document
    |> Ash.Query.filter(id in ^document_ids)
    |> destroy_all!()
  end

  defp destroy_all!(query) do
    Ash.bulk_destroy!(query, :destroy, %{},
      authorize?: false,
      return_errors?: true,
      strategy: [:atomic]
    )

    :ok
  end

  defp ids!(query) do
    query
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end

  defp count!(query), do: Ash.count!(query, authorize?: false)
end
