defmodule OfficeGraph.Repo.Migrations.CreateGitHubInstallationBindings do
  use Ecto.Migration

  def up do
    create table(:integration_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
      add :kind, :text, null: false
      add :secret_reference, :text, null: false
      add :status, :text, null: false, default: "active"
      add :rotated_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:github_installations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :restrict),
        null: false

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
      add :external_installation_id, :bigint, null: false
      add :app_slug, :text, null: false
      add :account_login, :text, null: false
      add :account_type, :text, null: false

      add :service_principal_id,
          references(:principals, type: :binary_id, on_delete: :restrict),
          null: false

      add :webhook_principal_id,
          references(:principals, type: :binary_id, on_delete: :restrict),
          null: false

      add :lifecycle_state, :text, null: false, default: "active"

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:github_permission_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :installation_id,
          references(:github_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :version, :integer, null: false
      add :captured_at, :utc_datetime_usec, null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    alter table(:github_installations) do
      add :current_permission_snapshot_id,
          references(:github_permission_snapshots, type: :binary_id, on_delete: :restrict)
    end

    create table(:github_permission_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :permission_snapshot_id,
          references(:github_permission_snapshots, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :text, null: false
      add :access_level, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create table(:github_installation_credentials, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :installation_id,
          references(:github_installations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :credential_id,
          references(:integration_credentials, type: :binary_id, on_delete: :restrict),
          null: false

      add :purpose, :text, null: false

      add :operation_id,
          references(:operation_correlations, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_installations, [:external_installation_id],
             name: :github_installations_external_installation_id_index
           )

    create unique_index(:github_installations, [:operation_id],
             name: :github_installations_operation_id_index
           )

    create unique_index(:github_permission_snapshots, [:installation_id, :version],
             name: :github_permission_snapshots_installation_version_index
           )

    create unique_index(:github_permission_entries, [:permission_snapshot_id, :name],
             name: :github_permission_entries_snapshot_name_index
           )

    create unique_index(:integration_credentials, [:organization_id, :kind, :secret_reference],
             name: :integration_credentials_scope_reference_index
           )

    create unique_index(:github_installation_credentials, [:installation_id, :purpose],
             name: :github_installation_credentials_installation_purpose_index
           )

    create constraint(:github_installations, :github_installations_lifecycle_state_valid,
             check: "lifecycle_state IN ('active', 'suspended', 'revoked')"
           )

    create constraint(:github_installations, :github_installations_account_type_valid,
             check: "account_type IN ('organization', 'user')"
           )

    create constraint(:github_installations, :github_installations_external_id_positive,
             check: "external_installation_id > 0"
           )

    create constraint(:github_permission_snapshots, :github_permission_snapshots_version_positive,
             check: "version > 0"
           )

    create constraint(:github_permission_entries, :github_permission_entries_access_level_valid,
             check: "access_level IN ('none', 'read', 'write', 'admin')"
           )

    create constraint(:integration_credentials, :integration_credentials_status_valid,
             check: "status IN ('active', 'rotating', 'revoked', 'expired')"
           )

    create constraint(:integration_credentials, :integration_credentials_kind_valid,
             check: "kind IN ('secret_reference')"
           )

    create constraint(
             :github_installation_credentials,
             :github_installation_credentials_purpose_valid,
             check: "purpose IN ('webhook_secret', 'app_private_key')"
           )

    execute("""
    INSERT INTO capabilities (id, key, description, inserted_at, updated_at)
    VALUES (
      md5('office_graph:capability:github.installation.bind')::uuid,
      'github.installation.bind',
      'github.installation.bind',
      NOW(),
      NOW()
    )
    ON CONFLICT (key) DO NOTHING
    """)

    execute("""
    INSERT INTO role_capabilities (id, role_id, capability_id, inserted_at, updated_at)
    SELECT
      md5('office_graph:role_capability:' || roles.id::text || ':github.installation.bind')::uuid,
      roles.id,
      capabilities.id,
      NOW(),
      NOW()
    FROM roles
    JOIN capabilities ON capabilities.key = 'github.installation.bind'
    WHERE roles.key = 'owner'
    ON CONFLICT (role_id, capability_id) DO NOTHING
    """)
  end

  def down do
    drop table(:github_installation_credentials)
    drop table(:github_permission_entries)

    alter table(:github_installations) do
      remove :current_permission_snapshot_id
    end

    drop table(:github_permission_snapshots)
    drop table(:github_installations)
    drop table(:integration_credentials)
  end
end
