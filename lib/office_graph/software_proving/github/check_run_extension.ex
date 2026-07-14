defmodule OfficeGraph.SoftwareProving.GitHub.CheckRunExtension do
  @moduledoc false

  use OfficeGraph.SoftwareProving.ProviderExtension,
    table: "github_check_runs",
    accept: [
      :check_run_id,
      :organization_id,
      :node_id,
      :database_id,
      :check_suite_database_id
    ]

  attributes do
    attribute :check_run_id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      writable?: true,
      public?: true

    attribute :organization_id, :uuid, allow_nil?: false, public?: true
    attribute :node_id, :string, allow_nil?: false, public?: true
    attribute :database_id, :integer, public?: true
    attribute :check_suite_database_id, :integer, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :check_run, OfficeGraph.SoftwareProving.CheckRun do
      source_attribute :check_run_id
      destination_attribute :id
      define_attribute? false
      public? true
    end
  end

  identities do
    identity :unique_organization_node_id, [:organization_id, :node_id]
  end
end
