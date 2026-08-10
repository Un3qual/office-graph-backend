defmodule OfficeGraph.TestSupport.MigrationConformanceSequenceResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "sequence_examples"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :integer,
      primary_key?: true,
      allow_nil?: false,
      generated?: true
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceIgnoredSequenceResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "ignored_sequence_examples"
    repo OfficeGraph.Repo
    migration_ignore_attributes [:ignored_counter]
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false

    attribute :ignored_counter, :integer,
      allow_nil?: false,
      generated?: true
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceIgnoredPrimaryKeyResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "ignored_primary_key_examples"
    repo OfficeGraph.Repo
    migration_ignore_attributes [:id]
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :name, :string, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceNetworkResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  resource do
    require_primary_key? false
  end

  postgres do
    table "network_endpoints"
    repo OfficeGraph.Repo
    migration_types address: :inet
  end

  attributes do
    attribute :address, :string, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceCompositeParentResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "composite_parents"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :uuid,
      source: :parent_id,
      primary_key?: true,
      allow_nil?: false

    attribute :scope_id, :uuid, source: :parent_scope, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceCompositeChildResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "composite_children"
    repo OfficeGraph.Repo

    references do
      reference :parent do
        name "composite_children_parent_fkey"
        match_with scope_id: :scope_id
      end
    end
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :parent_id, :uuid, source: :linked_parent_id, allow_nil?: false
    attribute :scope_id, :uuid, source: :child_scope, allow_nil?: false
  end

  relationships do
    belongs_to :parent, OfficeGraph.TestSupport.MigrationConformanceCompositeParentResource do
      source_attribute :parent_id
      destination_attribute :id
      define_attribute? false
      allow_nil? false
    end
  end
end
