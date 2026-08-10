defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Job do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.TestSupport.ConcurrencyCleanup.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "oban_jobs"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :integer, primary_key?: true, allow_nil?: false, public?: false
    attribute :args, :map, allow_nil?: true, public?: false
  end

  actions do
    defaults [:read, :destroy]
  end
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource OfficeGraph.TestSupport.ConcurrencyCleanup.Job
  end
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup.CanonicalData do
  @moduledoc false

  def destroy_all!(query) do
    query
    |> Ash.read!(authorize?: false)
    |> Enum.each(&destroy!/1)

    :ok
  end

  def force_update_all!(query, attributes) when is_list(attributes) do
    query
    |> Ash.read!(authorize?: false)
    |> Enum.each(&force_update!(&1, attributes))

    :ok
  end

  defp destroy!(%resource{} = record) do
    case Ash.DataLayer.destroy(resource, Ash.Changeset.new(record)) do
      :ok -> :ok
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end

  defp force_update!(%resource{} = record, attributes) do
    changeset =
      Enum.reduce(attributes, Ash.Changeset.new(record), fn {attribute, value}, changeset ->
        Ash.Changeset.force_change_attribute(changeset, attribute, value)
      end)
      |> Ash.Changeset.set_action_select()

    case Ash.DataLayer.update(resource, changeset) do
      {:ok, _record} -> :ok
      {:error, error} -> raise Ash.Error.to_error_class(error)
    end
  end
end

defmodule OfficeGraph.TestSupport.ConcurrencyCleanup do
  @moduledoc false

  alias OfficeGraph.Audit.AuditRecord

  alias OfficeGraph.Authorization.{
    AuthorizationDecision,
    PolicyBundle,
    Role,
    RoleAssignment,
    RoleCapability
  }

  alias OfficeGraph.Content.{
    Document,
    DocumentBlock,
    DocumentMark,
    DocumentReference,
    DocumentRevision
  }

  alias OfficeGraph.DurableDelivery.DomainEvent
  alias OfficeGraph.EnterpriseIdentity.EnterpriseConnection
  alias OfficeGraph.EnterpriseIdentity.Directory, as: EnterpriseDirectory
  alias OfficeGraph.EnterpriseIdentity.DirectoryGroup, as: EnterpriseDirectoryGroup
  alias OfficeGraph.EnterpriseIdentity.DirectoryMembership, as: EnterpriseDirectoryMembership
  alias OfficeGraph.EnterpriseIdentity.DirectorySyncEvent, as: EnterpriseDirectorySyncEvent
  alias OfficeGraph.EnterpriseIdentity.DirectoryUser, as: EnterpriseDirectoryUser
  alias OfficeGraph.EnterpriseIdentity.ExternalGroupRoleMapping

  alias OfficeGraph.Identity.{
    AuthenticationEvent,
    ExternalIdentityLink,
    Principal,
    PrincipalProfile,
    Session
  }

  alias OfficeGraph.Integrations.{ExternalSource, NormalizedIntakeEvent, RawArchive}
  alias OfficeGraph.NodeConversations.{Conversation, ConversationMessage}
  alias OfficeGraph.Operations.OperationCorrelation
  alias OfficeGraph.ProposedChanges.ProposedGraphChange
  alias OfficeGraph.Revisions.Revision
  alias OfficeGraph.Runs.{ExecutionObservation, Run, RunRequiredCheck}
  alias OfficeGraph.Tenancy.{Initiative, Organization, Workspace, Workstream}

  alias OfficeGraph.WorkGraph.{
    Artifact,
    EvidenceCandidate,
    EvidenceItem,
    GraphItem,
    GraphRelationship,
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck,
    VerificationResult
  }

  alias OfficeGraph.WorkPackets.{WorkPacket, WorkPacketVersion}
  alias OfficeGraph.WorkPackets.WorkPacketRequiredCheck, as: WorkPacketVersionRequiredCheck
  alias OfficeGraph.WorkPackets.WorkPacketSourceReference, as: WorkPacketVersionSource
  alias __MODULE__.{CanonicalData, Job}

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

    Enum.each(organization_ids, &cleanup_enterprise_identity_scope!/1)

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

    for resource <- [AuthorizationDecision, OperationCorrelation] do
      resource
      |> Ash.Query.filter(organization_id in ^organization_ids)
      |> destroy_all!()
    end

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

  def cleanup_bootstrap_scope!(organization_slug, owner_email) do
    cleanup_tenancy_scope!(organization_slug)
    cleanup_owner_principal!(owner_email)
  end

  defp cleanup_enterprise_identity_scope!(organization_id) do
    connection_ids =
      EnterpriseConnection
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> ids!()

    directory_ids =
      EnterpriseDirectory
      |> Ash.Query.filter(connection_id in ^connection_ids)
      |> ids!()

    user_ids =
      EnterpriseDirectoryUser
      |> Ash.Query.filter(directory_id in ^directory_ids)
      |> ids!()

    group_ids =
      EnterpriseDirectoryGroup
      |> Ash.Query.filter(directory_id in ^directory_ids)
      |> ids!()

    ExternalGroupRoleMapping
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> destroy_all!()

    EnterpriseDirectoryMembership
    |> Ash.Query.filter(directory_user_id in ^user_ids or directory_group_id in ^group_ids)
    |> destroy_all!()

    EnterpriseDirectorySyncEvent
    |> Ash.Query.filter(connection_id in ^connection_ids)
    |> destroy_all!()

    for {resource, ids} <- [
          {EnterpriseDirectoryUser, user_ids},
          {EnterpriseDirectoryGroup, group_ids},
          {EnterpriseDirectory, directory_ids},
          {EnterpriseConnection, connection_ids}
        ] do
      resource
      |> Ash.Query.filter(id in ^ids)
      |> destroy_all!()
    end
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
    |> CanonicalData.force_update_all!(current_version_id: nil)
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

  defp destroy_all!(query), do: CanonicalData.destroy_all!(query)

  defp ids!(query) do
    query
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end

  defp count!(query), do: Ash.count!(query, authorize?: false)
end
