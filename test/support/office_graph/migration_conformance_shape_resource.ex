defmodule OfficeGraph.TestSupport.MigrationConformanceShapeResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "shapes"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :name, :string, allow_nil?: false
  end

  identities do
    identity :unique_name, [:name]
  end
end
