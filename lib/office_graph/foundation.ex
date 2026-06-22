defmodule OfficeGraph.Foundation do
  @moduledoc """
  Public boundary for cross-cutting foundation contracts.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Identity,
      OfficeGraph.Tenancy
    ],
    exports: [Bootstrap]

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
end
