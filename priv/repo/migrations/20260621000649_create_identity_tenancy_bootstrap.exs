defmodule OfficeGraph.Repo.Migrations.CreateIdentityTenancyBootstrap do
  use Ecto.Migration

  def change do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false
      add :slug, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:organizations, [:slug])

    create table(:workspaces, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :text, null: false
      add :slug, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workspaces, [:organization_id, :slug])

    create table(:initiatives, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :text, null: false
      add :slug, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:initiatives, [:workspace_id, :slug])

    create table(:workstreams, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :initiative_id, references(:initiatives, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :text, null: false
      add :slug, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:workstreams, [:initiative_id, :slug])

    create table(:principals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :text, null: false
      add :kind, :text, null: false
      add :status, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:principals, [:email])

    create table(:principal_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict),
        null: false

      add :display_name, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:principal_profiles, [:principal_id])

    create table(:credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict),
        null: false

      add :provider, :text, null: false
      add :subject, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:credentials, [:provider, :subject])

    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict),
        null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict),
        null: false

      add :purpose, :text, null: false
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sessions, [:principal_id, :organization_id, :workspace_id, :purpose])

    create table(:capabilities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :text, null: false
      add :description, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:capabilities, [:key])

    create table(:roles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :key, :text, null: false
      add :name, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:roles, [:organization_id, :key])

    create table(:role_capabilities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role_id, references(:roles, type: :binary_id, on_delete: :delete_all), null: false

      add :capability_id, references(:capabilities, type: :binary_id, on_delete: :restrict),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:role_capabilities, [:role_id, :capability_id])

    create table(:role_assignments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict),
        null: false

      add :role_id, references(:roles, type: :binary_id, on_delete: :restrict), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:role_assignments, [:principal_id, :role_id, :organization_id])

    create table(:policy_bundles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :version, :integer, null: false
      add :status, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:policy_bundles, [:organization_id, :version])
  end
end
