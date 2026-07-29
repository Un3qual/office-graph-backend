defmodule OfficeGraph.GitHubIntegration.CommandInputs.InstallationPermission do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :name, :string,
      allow_nil?: false,
      constraints: [match: ~r/^[a-z][a-z0-9_]*$/]

    field :access_level, :string, allow_nil?: false
  end

  use AshGraphql.Type

  @impl true
  def graphql_input_type(_constraints), do: :github_installation_permission_input
end

defmodule OfficeGraph.GitHubIntegration.CommandResults.CredentialBinding do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :id, :uuid, allow_nil?: false
    field :purpose, :string, allow_nil?: false
    field :kind, :string, allow_nil?: false
    field :status, :string, allow_nil?: false
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :github_credential_command_result
end

defmodule OfficeGraph.GitHubIntegration.CommandResults.BindInstallation do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId
  alias OfficeGraph.GitHubIntegration.CommandResults.CredentialBinding

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :installation, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.GitHubIntegration.Installation]

    field :permission_snapshot, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.GitHubIntegration.PermissionSnapshot]

    field :permissions, {:array, :struct},
      allow_nil?: false,
      constraints: [items: [instance_of: OfficeGraph.GitHubIntegration.PermissionEntry]]

    field :credentials, {:array, CredentialBinding}, allow_nil?: false
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :bind_github_installation_payload

  def from_result(result) do
    new(
      command: "bind_github_installation",
      operation_id: result.operation.id,
      affected_ids: [
        TypedId.new!(type: "github_installation", id: result.installation.id),
        TypedId.new!(type: "github_permission_snapshot", id: result.permission_snapshot.id)
      ],
      installation: result.installation,
      permission_snapshot: result.permission_snapshot,
      permissions: result.permissions,
      credentials: Enum.map(result.credentials, &CredentialBinding.new!/1)
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.GitHubIntegration.CommandResults.BindInstallation do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        installation: %{
          id: result.installation.id,
          organization_id: result.installation.organization_id,
          workspace_id: result.installation.workspace_id,
          external_installation_id:
            Integer.to_string(result.installation.external_installation_id),
          lifecycle_state: result.installation.lifecycle_state,
          service_principal_id: result.installation.service_principal_id,
          webhook_principal_id: result.installation.webhook_principal_id
        },
        permission_snapshot: %{
          id: result.permission_snapshot.id,
          version: result.permission_snapshot.version
        },
        permissions:
          Enum.map(result.permissions, &%{name: &1.name, access_level: &1.access_level}),
        credentials:
          Enum.map(
            result.credentials,
            &Map.take(&1, [:id, :purpose, :kind, :status])
          )
      },
      options
    )
  end
end

defmodule OfficeGraph.GitHubIntegration.Installation do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.GitHubIntegration.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "github_installations"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_external_installation:
                           "github_installations_external_installation_id_index",
                         unique_operation: "github_installations_operation_id_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :external_installation_id, :integer, allow_nil?: false, public?: true
    attribute :app_slug, :string, allow_nil?: false, public?: true
    attribute :account_login, :string, allow_nil?: false, public?: true
    attribute :account_type, :string, allow_nil?: false, public?: true

    attribute :lifecycle_state, :string,
      allow_nil?: false,
      default: "active",
      public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? true
      pagination keyset?: true, countable: false, required?: false
    end

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :external_installation_id,
        :app_slug,
        :account_login,
        :account_type,
        :service_principal_id,
        :webhook_principal_id,
        :lifecycle_state,
        :operation_id
      ]

      validate one_of(:account_type, ~w(organization user))
      validate one_of(:lifecycle_state, ~w(active suspended revoked))
      public? false
    end

    update :set_permission_snapshot do
      accept [:current_permission_snapshot_id]
      require_atomic? false
      public? false
    end

    update :set_lifecycle do
      accept [:lifecycle_state]
      validate one_of(:lifecycle_state, ~w(active suspended revoked))
      require_atomic? false
      public? false
    end

    action :bind_github_installation,
           OfficeGraph.GitHubIntegration.CommandResults.BindInstallation do
      argument :idempotency_key, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :workspace_id, :uuid

      argument :external_installation_id, :string,
        allow_nil?: false,
        constraints: [match: ~r/^[1-9][0-9]*$/]

      argument :app_slug, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :account_login, :string, allow_nil?: false, constraints: [match: ~r/\S/]
      argument :account_type, :string, allow_nil?: false

      argument :service_principal_email, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :webhook_principal_email, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :webhook_secret_reference, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :app_private_key_reference, :string,
        allow_nil?: false,
        constraints: [match: ~r/\S/]

      argument :permissions,
               {:array, OfficeGraph.GitHubIntegration.CommandInputs.InstallationPermission},
               allow_nil?: false

      validate argument_in(:account_type, ~w(organization user))

      run fn input, context ->
        OfficeGraph.GitHubIntegration.Actions.BindInstallation.run(input, [], context)
      end
    end
  end

  identities do
    identity :unique_external_installation, [:external_installation_id]
    identity :unique_operation, [:operation_id]
  end

  relationships do
    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      public? true
      attribute_public? true
    end

    belongs_to :governing_workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      public? true
      attribute_public? true
    end

    belongs_to :service_principal, OfficeGraph.Identity.Principal do
      source_attribute :service_principal_id
      destination_attribute :id
      public? true
      attribute_public? true
    end

    belongs_to :webhook_principal, OfficeGraph.Identity.Principal do
      source_attribute :webhook_principal_id
      destination_attribute :id
      public? true
      attribute_public? true
    end

    belongs_to :current_permission_snapshot, OfficeGraph.GitHubIntegration.PermissionSnapshot do
      source_attribute :current_permission_snapshot_id
      destination_attribute :id
      public? true
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      public? true
      attribute_public? true
    end

    has_many :permission_snapshots, OfficeGraph.GitHubIntegration.PermissionSnapshot do
      public? true
    end

    has_many :credential_bindings, OfficeGraph.GitHubIntegration.InstallationCredential
    has_many :sync_outcomes, OfficeGraph.GitHubIntegration.SyncOutcome

    has_many :outbound_actions, OfficeGraph.GitHubIntegration.OutboundAction do
      public? true
    end
  end

  policies do
    policy action(:bind_github_installation) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :github_installation_bind}
    end

    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       (is_nil(workspace_id) or workspace_id == ^actor(:workspace_id))
                   )
    end
  end

  graphql do
    type :github_installation
  end

  json_api do
    type "github_installation"
  end
end
