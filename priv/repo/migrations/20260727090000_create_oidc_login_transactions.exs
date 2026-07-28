defmodule OfficeGraph.Repo.Migrations.CreateOidcLoginTransactions do
  use Ecto.Migration

  def change do
    create table(:oidc_login_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:oidc_login_transactions, [:expires_at])
  end
end
