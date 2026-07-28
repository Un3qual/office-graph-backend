defmodule OfficeGraph.ApiSupport do
  @moduledoc """
  Local API owner bootstrap support.
  """

  use Boundary,
    deps: [OfficeGraph.Foundation, OfficeGraph.Identity],
    exports: []

  alias OfficeGraph.{Foundation, Identity}

  def bootstrap_local_api_owner do
    if Application.get_env(:office_graph, :allow_local_api_owner_bootstrap, false) do
      Foundation.bootstrap_local_owner([])
    else
      {:error, :forbidden}
    end
  end

  def bootstrap_local_human_session do
    with {:ok, bootstrap} <- bootstrap_local_api_owner(),
         {:ok, linked} <-
           Identity.reconcile_oidc_identity(
             %{
               "sub" => "local-owner",
               "email" => bootstrap.principal.email,
               "email_verified" => true,
               "name" => bootstrap.profile.display_name
             },
             provider: "local_fixture",
             provider_tenant: "office_graph",
             account_linking_policy: :verified_email_existing_principal
           ),
         {:ok, issued} <-
           Identity.issue_human_session(
             linked.principal,
             linked.external_identity_link,
             %{
               organization_id: bootstrap.organization.id,
               workspace_id: bootstrap.workspace.id
             },
             authentication_method: "oidc",
             source_surface: "local_fixture",
             trace_id: Ecto.UUID.generate()
           ) do
      {:ok, %{bootstrap: bootstrap, human_session: issued}}
    end
  end
end
