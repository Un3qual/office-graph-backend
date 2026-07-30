defmodule OfficeGraph.Foundation do
  @moduledoc """
  Public boundary for cross-cutting foundation contracts.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authentication,
      OfficeGraph.Authorization,
      OfficeGraph.Identity,
      OfficeGraph.Tenancy
    ],
    exports: [Bootstrap]

  alias OfficeGraph.Authentication.LocalDevelopmentFixtures
  alias OfficeGraph.Authorization
  alias OfficeGraph.Foundation.Bootstrap
  alias OfficeGraph.Identity
  alias OfficeGraph.Tenancy

  @defaults [
    organization_name: "Office Graph",
    organization_slug: "office-graph",
    workspace_name: "Default Workspace",
    workspace_slug: "default",
    initiative_name: "Walking Skeleton",
    initiative_slug: "walking-skeleton",
    owner_email: "owner@office-graph.local",
    owner_name: "Office Graph Owner"
  ]

  def bootstrap_local_owner(attrs) do
    attrs = Keyword.merge(@defaults, attrs)

    with {:ok, tenant} <- Tenancy.ensure_local_scope(attrs),
         {:ok, identity} <- Identity.ensure_owner(attrs),
         {:ok, authorization} <- Authorization.ensure_owner_role(identity.principal, tenant),
         {:ok, session} <-
           Identity.ensure_session_context(identity.principal, tenant, authorization.capabilities) do
      {:ok,
       %Bootstrap{
         organization: tenant.organization,
         workspace: tenant.workspace,
         initiative: tenant.initiative,
         principal: identity.principal,
         profile: identity.profile,
         session: session,
         role_assignment: authorization.role_assignment,
         policy_bundle: authorization.policy_bundle
       }}
    end
  end

  def seed_local_development_fixtures(attrs \\ []) when is_list(attrs) do
    with {:ok, owner_fixture} <- LocalDevelopmentFixtures.fetch("owner"),
         {:ok, bootstrap} <- bootstrap_local_owner(owner_bootstrap_attrs(attrs, owner_fixture)),
         {:ok, fixtures} <- seed_fixture_records(bootstrap) do
      {:ok, %{bootstrap: bootstrap, fixtures: fixtures}}
    end
  end

  defp owner_bootstrap_attrs(attrs, owner_fixture) do
    attrs
    |> Keyword.put(:owner_email, owner_fixture.email)
    |> Keyword.put(:owner_name, owner_fixture.display_name)
  end

  defp seed_fixture_records(bootstrap) do
    LocalDevelopmentFixtures.all()
    |> Enum.reduce_while({:ok, %{}}, fn fixture, {:ok, fixtures} ->
      with {:ok, identity} <- Identity.ensure_local_development_identity(fixture),
           {:ok, role_assignment} <- ensure_fixture_role(bootstrap, fixture, identity) do
        seeded_fixture = %{
          definition: fixture,
          identity: identity,
          role_assignment: role_assignment
        }

        {:cont, {:ok, Map.put(fixtures, fixture.key, seeded_fixture)}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp ensure_fixture_role(bootstrap, %{role_profile: :owner}, _identity) do
    {:ok, bootstrap.role_assignment}
  end

  defp ensure_fixture_role(bootstrap, fixture, identity) do
    tenant = %{organization: bootstrap.organization, workspace: bootstrap.workspace}

    with {:ok, role_setup} <-
           Authorization.ensure_local_development_role(identity.principal, tenant, fixture) do
      {:ok, role_setup.role_assignment}
    end
  end
end
