defmodule OfficeGraph.Runs.RunRequiredCheck do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Runs.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "run_required_checks"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    uuid_primary_key :id, writable?: true
    attribute :run_id, :uuid, allow_nil?: false, public?: true
    attribute :verification_check_id, :uuid, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :workspace_id, :uuid, allow_nil?: false, public?: true
    attribute :state, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :run_id,
        :verification_check_id,
        :organization_id,
        :workspace_id,
        :state
      ]
    end

    update :mark_satisfied do
      public? false
      accept []
      change set_attribute(:state, "satisfied")
    end
  end

  identities do
    identity :unique_run_check, [:run_id, :verification_check_id]
  end
end
