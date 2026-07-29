defmodule OfficeGraph.Authorization.RoleSetup do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :role_assignment, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Authorization.RoleAssignment]

    field :policy_bundle, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Authorization.PolicyBundle]

    field :capabilities, {:array, :string}, allow_nil?: false
  end
end

defmodule OfficeGraph.Authorization.Actions.EnsureRole do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Authorization.{
    Capability,
    PolicyBundle,
    Role,
    RoleAssignment,
    RoleCapability,
    RoleSetup
  }

  @impl true
  def run(input, [mode: :owner], _context) do
    attrs = input.arguments

    with {:ok, capabilities_by_key} <-
           ensure_capabilities(attrs.recognized_capability_keys),
         {:ok, role} <-
           ensure(Role, %{
             organization_id: attrs.organization_id,
             key: "owner",
             name: "Owner"
           }),
         :ok <-
           ensure_role_capabilities(
             role.id,
             capabilities_by_key,
             attrs.owner_capability_keys
           ),
         {:ok, role_assignment} <-
           ensure(RoleAssignment, %{
             principal_id: attrs.principal_id,
             role_id: role.id,
             organization_id: attrs.organization_id,
             workspace_id: attrs.workspace_id
           }),
         {:ok, policy_bundle} <-
           ensure(PolicyBundle, %{
             organization_id: attrs.organization_id,
             version: 1,
             status: "active"
           }) do
      RoleSetup.new(
        role_assignment: role_assignment,
        policy_bundle: policy_bundle,
        capabilities: attrs.owner_capability_keys
      )
    end
  end

  def run(input, [mode: :system], _context) do
    attrs = input.arguments

    with {:ok, capabilities_by_key} <- ensure_capabilities(attrs.capability_keys),
         {:ok, role} <-
           ensure(Role, %{
             organization_id: attrs.organization_id,
             key: attrs.role_key,
             name: attrs.role_name
           }),
         :ok <-
           ensure_role_capabilities(role.id, capabilities_by_key, attrs.capability_keys),
         {:ok, _role_assignment} <-
           ensure(RoleAssignment, %{
             principal_id: attrs.principal_id,
             role_id: role.id,
             organization_id: attrs.organization_id,
             workspace_id: attrs.workspace_id
           }) do
      :ok
    end
  end

  defp ensure_capabilities(keys) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, capabilities_by_key} ->
      case ensure(Capability, %{key: key, description: key}) do
        {:ok, capability} ->
          {:cont, {:ok, Map.put(capabilities_by_key, key, capability)}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end

  defp ensure_role_capabilities(role_id, capabilities_by_key, capability_keys) do
    Enum.reduce_while(capability_keys, :ok, fn capability_key, :ok ->
      capability = Map.fetch!(capabilities_by_key, capability_key)

      case ensure(RoleCapability, %{
             role_id: role_id,
             capability_id: capability.id
           }) do
        {:ok, _role_capability} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp ensure(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:ensure, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> case do
      {:ok, record, _notifications} -> {:ok, record}
      {:error, error} -> {:error, error}
    end
  end
end

defmodule OfficeGraph.Authorization.Role do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Authorization.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "roles"
    repo OfficeGraph.Repo
    migrate? false

    identity_index_names unique_key: "roles_organization_id_key_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :key, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true

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

    has_many :role_capabilities, OfficeGraph.Authorization.RoleCapability do
      source_attribute :id
      destination_attribute :role_id
    end

    has_many :assignments, OfficeGraph.Authorization.RoleAssignment do
      source_attribute :id
      destination_attribute :role_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :organization_id, :key, :name]
    end

    create :ensure do
      public? false
      accept [:organization_id, :key, :name]
      upsert? true
      upsert_identity :unique_key
      upsert_fields []
      return_skipped_upsert? true
    end

    action :ensure_owner_role, OfficeGraph.Authorization.RoleSetup do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Authorization.Capability,
        OfficeGraph.Authorization.RoleCapability,
        OfficeGraph.Authorization.RoleAssignment,
        OfficeGraph.Authorization.PolicyBundle
      ]

      argument :principal_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid, allow_nil?: false

      argument :recognized_capability_keys, {:array, :string}, allow_nil?: false
      argument :owner_capability_keys, {:array, :string}, allow_nil?: false

      run {OfficeGraph.Authorization.Actions.EnsureRole, mode: :owner}
    end

    action :ensure_system_role do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Authorization.Capability,
        OfficeGraph.Authorization.RoleCapability,
        OfficeGraph.Authorization.RoleAssignment
      ]

      argument :principal_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid
      argument :role_key, :string, allow_nil?: false
      argument :role_name, :string, allow_nil?: false
      argument :capability_keys, {:array, :string}, allow_nil?: false

      run {OfficeGraph.Authorization.Actions.EnsureRole, mode: :system}
    end
  end

  identities do
    identity :unique_key, [:organization_id, :key]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(organization_id == ^actor(:organization_id))
    end
  end
end
