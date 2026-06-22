defmodule OfficeGraph.Repo.Migrations.MakeSessionsUniqueByActiveContext do
  use Ecto.Migration

  def change do
    drop_if_exists index(:sessions, [:principal_id, :organization_id, :workspace_id, :purpose])

    create unique_index(:sessions, [:principal_id, :organization_id, :workspace_id, :purpose],
             where: "revoked_at IS NULL"
           )
  end
end
