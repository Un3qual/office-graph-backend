defmodule OfficeGraph.EnterpriseIdentity.Directory do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.EnterpriseIdentity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "enterprise_directories"
    repo OfficeGraph.Repo

    identity_index_names provider_directory: "enterprise_directories_provider_directory_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :provider_directory_id, :string, allow_nil?: false, public?: true
    attribute :status, :string, allow_nil?: false, public?: true
    attribute :provider_updated_at, :utc_datetime_usec, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :connection, OfficeGraph.EnterpriseIdentity.EnterpriseConnection do
      allow_nil? false
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      allow_nil? false
      attribute_public? true
    end

    has_many :users, OfficeGraph.EnterpriseIdentity.DirectoryUser do
      destination_attribute :directory_id
    end

    has_many :groups, OfficeGraph.EnterpriseIdentity.DirectoryGroup do
      destination_attribute :directory_id
    end

    has_many :sync_events, OfficeGraph.EnterpriseIdentity.DirectorySyncEvent do
      destination_attribute :directory_id
    end
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      public? false

      accept [
        :id,
        :connection_id,
        :operation_id,
        :provider_directory_id,
        :status,
        :provider_updated_at
      ]

      validate one_of(:status, ~w(active disabled deleted))
    end

    update :set_lifecycle do
      public? false
      accept [:status, :provider_updated_at]

      validate one_of(:status, ~w(active disabled deleted)),
        where: [changing(:status)]

      require_atomic? false
    end

    action :apply_event,
           Module.concat([OfficeGraph, EnterpriseIdentity, DirectoryApplyResult]) do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Operations.OperationCorrelation,
        OfficeGraph.Identity.Principal,
        OfficeGraph.Identity.ExternalIdentityLink,
        OfficeGraph.EnterpriseIdentity.DirectoryUser,
        OfficeGraph.EnterpriseIdentity.DirectoryGroup,
        OfficeGraph.EnterpriseIdentity.DirectoryMembership
      ]

      argument :directory_id, :uuid, allow_nil?: false
      argument :operation_id, :uuid, allow_nil?: false

      argument :event,
               OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.DirectoryEvent,
               allow_nil?: false

      run Module.concat([OfficeGraph, EnterpriseIdentity, Actions, ApplyDirectoryEvent])
    end
  end

  identities do
    identity :provider_directory, [:provider_directory_id]
  end
end
