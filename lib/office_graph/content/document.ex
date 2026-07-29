defmodule OfficeGraph.Content.Actions.PersistPlainDocument do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Content.{Document, DocumentBlock, DocumentRevision}

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments

    with {:ok, document, _document_notifications} <-
           create(Document, %{
             organization_id: attrs.organization_id,
             workspace_id: attrs.workspace_id,
             plain_text: attrs.plain_text
           }),
         {:ok, _block, _block_notifications} <-
           create(DocumentBlock, %{
             document_id: document.id,
             position: 0,
             block_type: "paragraph",
             text: attrs.plain_text
           }),
         {:ok, _revision, _revision_notifications} <-
           create(DocumentRevision, %{
             document_id: document.id,
             operation_id: attrs.operation_id,
             revision_number: 1,
             semantic_summary: "initial"
           }) do
      # Content has no notifiers. Requesting and deliberately consuming nested
      # notifications keeps this action quiet even while legacy callers still
      # wrap it in an outer transaction.
      {:ok, document}
    end
  end

  defp create(resource, attrs) do
    Ash.create(resource, attrs,
      action: :create,
      authorize?: false,
      return_notifications?: true
    )
  end
end

defmodule OfficeGraph.Content.Document do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Content.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "documents"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "documents_organization_id_fkey",
                      workspace_id: "documents_workspace_id_fkey"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :plain_text, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :blocks, OfficeGraph.Content.DocumentBlock do
      source_attribute :id
      destination_attribute :document_id
    end

    has_many :references, OfficeGraph.Content.DocumentReference do
      source_attribute :id
      destination_attribute :document_id
    end

    has_many :revisions, OfficeGraph.Content.DocumentRevision do
      source_attribute :id
      destination_attribute :document_id
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :organization_id, :workspace_id, :plain_text]
    end

    action :persist_plain_document, :struct do
      public? false
      transaction? true
      constraints instance_of: __MODULE__

      touches_resources [
        OfficeGraph.Content.DocumentBlock,
        OfficeGraph.Content.DocumentRevision
      ]

      argument :organization_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid, allow_nil?: false
      argument :operation_id, :uuid, allow_nil?: false
      argument :plain_text, :string, allow_nil?: false

      run OfficeGraph.Content.Actions.PersistPlainDocument
    end
  end
end
