defmodule OfficeGraph.Repo.Migrations.ExpandExternalIdentityEmailConflicts do
  use Ecto.Migration

  def up do
    drop_if_exists(
      index(
        :external_identity_links,
        [:provider, :provider_tenant, :verified_email]
      )
    )

    create index(:external_identity_links, [:verified_email])
  end

  def down do
    drop_if_exists(index(:external_identity_links, [:verified_email]))

    create index(
             :external_identity_links,
             [:provider, :provider_tenant, :verified_email]
           )
  end
end
