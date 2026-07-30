defmodule OfficeGraph.Tenancy.LocalScope do
  @moduledoc false

  use Ash.TypedStruct
  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Tenancy.{Initiative, Organization, Workspace, Workstream}

  typed_struct do
    field :organization, :struct,
      allow_nil?: false,
      constraints: [instance_of: Organization]

    field :workspace, :struct,
      allow_nil?: false,
      constraints: [instance_of: Workspace]

    field :initiative, :struct,
      allow_nil?: false,
      constraints: [instance_of: Initiative]
  end

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments

    with {:ok, organization} <-
           ensure(Organization, %{
             name: attrs.organization_name,
             slug: attrs.organization_slug
           }),
         {:ok, workspace} <-
           ensure(Workspace, %{
             organization_id: organization.id,
             name: attrs.workspace_name,
             slug: attrs.workspace_slug
           }),
         {:ok, initiative} <-
           ensure(Initiative, %{
             organization_id: organization.id,
             workspace_id: workspace.id,
             name: attrs.initiative_name,
             slug: attrs.initiative_slug
           }),
         {:ok, _workstream} <-
           ensure(Workstream, %{
             organization_id: organization.id,
             workspace_id: workspace.id,
             initiative_id: initiative.id,
             name: "Default Workstream",
             slug: "default"
           }) do
      new(
        organization: organization,
        workspace: workspace,
        initiative: initiative
      )
    end
  end

  defp ensure(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:ensure, attrs)
    |> Ash.create(authorize?: false)
  end
end

defmodule OfficeGraph.Tenancy.Organization do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Tenancy.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo OfficeGraph.Repo

    identity_index_names unique_slug: "organizations_slug_index"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    has_many :workspaces, OfficeGraph.Tenancy.Workspace do
      source_attribute :id
      destination_attribute :organization_id
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:id, :name, :slug]
    end

    create :ensure do
      public? false
      accept [:name, :slug]
      upsert? true
      upsert_identity :unique_slug
      upsert_fields []
      return_skipped_upsert? true
    end

    action :ensure_local_scope, OfficeGraph.Tenancy.LocalScope do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Tenancy.Workspace,
        OfficeGraph.Tenancy.Initiative,
        OfficeGraph.Tenancy.Workstream
      ]

      argument :organization_name, :string, allow_nil?: false
      argument :organization_slug, :string, allow_nil?: false
      argument :workspace_name, :string, allow_nil?: false
      argument :workspace_slug, :string, allow_nil?: false
      argument :initiative_name, :string, allow_nil?: false
      argument :initiative_slug, :string, allow_nil?: false

      run OfficeGraph.Tenancy.LocalScope
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(id == ^actor(:organization_id))
    end
  end
end
