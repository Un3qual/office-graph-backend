defmodule OfficeGraph.Identity.ResourceContractTest do
  use OfficeGraph.DataCase, async: true

  alias OfficeGraph.Identity.{ExternalIdentityLink, OidcLoginTransaction}

  test "OIDC transaction expiry pruning has a declarative lookup index" do
    assert %AshPostgres.CustomIndex{
             name: "oidc_login_transactions_expires_at_index",
             fields: [:expires_at],
             unique: false
           } = custom_index(OidcLoginTransaction, "oidc_login_transactions_expires_at_index")
  end

  test "external identity reconciliation has declarative email and principal indexes" do
    assert %AshPostgres.CustomIndex{
             name: "external_identity_links_verified_email_index",
             fields: [:verified_email],
             unique: false
           } =
             custom_index(
               ExternalIdentityLink,
               "external_identity_links_verified_email_index"
             )

    assert %AshPostgres.CustomIndex{
             name: "external_identity_links_principal_id_index",
             fields: [:principal_id],
             unique: false
           } =
             custom_index(
               ExternalIdentityLink,
               "external_identity_links_principal_id_index"
             )
  end

  defp custom_index(resource, name) do
    Enum.find(AshPostgres.DataLayer.Info.custom_indexes(resource), &(&1.name == name))
  end
end
