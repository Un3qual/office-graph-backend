defmodule OfficeGraph.SoftwareProving.Commit do
  @moduledoc false

  use OfficeGraph.SoftwareProving.Resource,
    table: "commits",
    accept: [:repository_id, :oid, :summary, :authored_at, :committed_at]

  attributes do
    attribute :repository_id, :uuid, allow_nil?: false, public?: true
    attribute :oid, :string, allow_nil?: false, public?: true
    attribute :summary, :string, public?: true
    attribute :authored_at, :utc_datetime_usec, public?: true
    attribute :committed_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :repository, OfficeGraph.SoftwareProving.Repository do
      source_attribute :repository_id
      destination_attribute :id
      define_attribute? false
      public? true
    end
  end

  identities do
    identity :unique_repository_oid, [:repository_id, :oid]
  end
end
