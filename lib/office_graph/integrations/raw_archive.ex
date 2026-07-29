defmodule OfficeGraph.Integrations.ProviderArchiveResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false

    field :archive, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Integrations.RawArchive]
  end

  def created(archive), do: new(status: "created", archive: archive)
  def replayed(archive), do: new(status: "replayed", archive: archive)
end

defmodule OfficeGraph.Integrations.Actions.ArchiveProviderDelivery do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Integrations.{
    ExternalSource,
    ProviderArchiveResult,
    RawArchive
  }

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments

    with {:ok, %ExternalSource{kind: "provider"}} <- locked_source(attrs.source_id),
         {:ok, existing} <- existing_archive(attrs.source_id, attrs.external_delivery_id) do
      case existing do
        nil -> create_archive(attrs)
        archive -> ProviderArchiveResult.replayed(archive)
      end
    else
      {:ok, _missing_or_invalid_source} -> {:error, :invalid_provider_source}
      {:error, error} -> {:error, error}
    end
  end

  defp locked_source(source_id) do
    ExternalSource
    |> Ash.Query.filter(id == ^source_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp existing_archive(source_id, external_delivery_id) do
    RawArchive
    |> Ash.Query.filter(source_id == ^source_id and external_delivery_id == ^external_delivery_id)
    |> Ash.read_one(authorize?: false)
  end

  defp create_archive(attrs) do
    attrs =
      Map.take(attrs, [
        :organization_id,
        :workspace_id,
        :source_id,
        :operation_id,
        :content_hash,
        :archive_kind,
        :external_delivery_id,
        :provider_event,
        :external_installation_id,
        :body
      ])

    RawArchive
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, archive, _notifications} -> ProviderArchiveResult.created(archive)
      {:error, error} -> {:error, error}
    end
  end
end

defmodule OfficeGraph.Integrations.RawArchive do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Integrations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "raw_archives"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "raw_archives_organization_id_fkey",
                      workspace_id: "raw_archives_workspace_id_fkey",
                      source_id: "raw_archives_source_id_fkey",
                      operation_id: "raw_archives_operation_id_fkey"

    identity_index_names provider_delivery: "raw_archives_provider_delivery_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :content_hash, :string, allow_nil?: false, public?: true
    attribute :archive_kind, :string, allow_nil?: false, default: "manual_intake", public?: true
    attribute :external_delivery_id, :string, public?: true
    attribute :provider_event, :string, public?: true
    attribute :external_installation_id, :integer, public?: true

    attribute :body, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false]

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :external_source, OfficeGraph.Integrations.ExternalSource do
      source_attribute :source_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      attribute_public? true
    end

    has_many :normalized_events, OfficeGraph.Integrations.NormalizedIntakeEvent do
      source_attribute :id
      destination_attribute :raw_archive_id
    end
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
        :source_id,
        :operation_id,
        :content_hash,
        :archive_kind,
        :external_delivery_id,
        :provider_event,
        :external_installation_id,
        :body
      ]
    end

    action :archive_provider_delivery, OfficeGraph.Integrations.ProviderArchiveResult do
      public? false
      transaction? true
      touches_resources [OfficeGraph.Integrations.ExternalSource]

      argument :organization_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid
      argument :source_id, :uuid, allow_nil?: false
      argument :operation_id, :uuid, allow_nil?: false
      argument :content_hash, :string, allow_nil?: false
      argument :archive_kind, :string, allow_nil?: false
      argument :external_delivery_id, :string, allow_nil?: false
      argument :provider_event, :string
      argument :external_installation_id, :integer
      argument :body, :string, allow_nil?: false, constraints: [trim?: false]

      run OfficeGraph.Integrations.Actions.ArchiveProviderDelivery
    end
  end

  identities do
    identity :provider_delivery, [:source_id, :external_delivery_id],
      where: expr(not is_nil(external_delivery_id))
  end
end
