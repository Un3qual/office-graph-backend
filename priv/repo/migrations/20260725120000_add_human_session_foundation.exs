defmodule OfficeGraph.Repo.Migrations.AddHumanSessionFoundation do
  use Ecto.Migration

  def change do
    create table(:external_identity_links, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict)

      add :provider, :text, null: false
      add :provider_tenant, :text, null: false
      add :subject, :text, null: false
      add :verified_email, :text, null: false
      add :status, :text, null: false
      add :linking_state, :text, null: false
      add :review_reason, :text
      add :first_linked_at, :utc_datetime_usec
      add :last_authenticated_at, :utc_datetime_usec
      add :disabled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:external_identity_links, [:provider, :provider_tenant, :subject])

    create index(
             :external_identity_links,
             [:provider, :provider_tenant, :verified_email]
           )

    create index(:external_identity_links, [:principal_id])

    create constraint(:external_identity_links, :external_identity_links_status_check,
             check: "status IN ('active', 'review_required', 'disabled')"
           )

    create constraint(
             :external_identity_links,
             :external_identity_links_linking_state_check,
             check: "linking_state IN ('linked', 'review_required')"
           )

    create constraint(
             :external_identity_links,
             :external_identity_links_active_principal_check,
             check:
               "status <> 'active' OR (principal_id IS NOT NULL AND linking_state = 'linked')"
           )

    create constraint(
             :external_identity_links,
             :external_identity_links_review_state_check,
             check: "status <> 'review_required' OR linking_state = 'review_required'"
           )

    alter table(:sessions) do
      add :external_identity_link_id,
          references(:external_identity_links, type: :binary_id, on_delete: :restrict)

      add :authentication_method, :text
      add :issued_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :source_surface, :text
      add :trace_id, :text
    end

    create index(:sessions, [:external_identity_link_id])
    create index(:sessions, [:expires_at], where: "revoked_at IS NULL")

    create constraint(:sessions, :sessions_human_web_metadata_check,
             check: """
             purpose <> 'human_web' OR (
               external_identity_link_id IS NOT NULL AND
               authentication_method IS NOT NULL AND
               issued_at IS NOT NULL AND
               expires_at IS NOT NULL AND
               source_surface IS NOT NULL AND
               trace_id IS NOT NULL AND
               expires_at > issued_at
             )
             """
           )

    create table(:authentication_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :principal_id, references(:principals, type: :binary_id, on_delete: :restrict)

      add :external_identity_link_id,
          references(:external_identity_links, type: :binary_id, on_delete: :restrict)

      add :session_id, references(:sessions, type: :binary_id, on_delete: :restrict)

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :restrict)

      add :workspace_id, references(:workspaces, type: :binary_id, on_delete: :restrict)
      add :event, :text, null: false
      add :result, :text, null: false
      add :reason, :text
      add :authentication_method, :text, null: false
      add :source_surface, :text, null: false
      add :trace_id, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:authentication_events, [:principal_id, :inserted_at])
    create index(:authentication_events, [:external_identity_link_id, :inserted_at])
    create index(:authentication_events, [:session_id, :inserted_at])
    create index(:authentication_events, [:organization_id, :workspace_id, :inserted_at])

    create constraint(:authentication_events, :authentication_events_result_check,
             check: "result IN ('succeeded', 'rejected')"
           )

    execute(
      """
      ALTER TABLE authentication_events
      ADD CONSTRAINT authentication_events_workspace_scope_fkey
      FOREIGN KEY (workspace_id, organization_id)
      REFERENCES workspaces(id, organization_id)
      """,
      "ALTER TABLE authentication_events DROP CONSTRAINT authentication_events_workspace_scope_fkey"
    )
  end
end
