defmodule OfficeGraph.ConcurrencyCleanupTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Identity.Principal
  alias OfficeGraph.Tenancy.Organization
  alias OfficeGraph.TestSupport.ConcurrencyCleanup

  test "cleans a bootstrapped scope through the canonical resource contracts" do
    suffix = System.unique_integer([:positive])
    organization_slug = "cleanup-#{suffix}"
    owner_email = "cleanup-#{suffix}@example.test"

    assert {:ok, bootstrap} =
             Foundation.bootstrap_local_owner(
               organization_name: "Cleanup #{suffix}",
               organization_slug: organization_slug,
               workspace_slug: "workspace-#{suffix}",
               initiative_slug: "initiative-#{suffix}",
               owner_email: owner_email
             )

    assert Ash.get!(Organization, bootstrap.organization.id, authorize?: false)
    assert Ash.get!(Principal, bootstrap.principal.id, authorize?: false)

    ConcurrencyCleanup.cleanup_tenancy_scope!(organization_slug)
    ConcurrencyCleanup.cleanup_owner_principal!(owner_email)

    assert {:ok, nil} =
             Ash.get(Organization, bootstrap.organization.id,
               authorize?: false,
               not_found_error?: false
             )

    assert {:ok, nil} =
             Ash.get(Principal, bootstrap.principal.id,
               authorize?: false,
               not_found_error?: false
             )
  end
end
