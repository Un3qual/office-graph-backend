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

defmodule OfficeGraph.TestSupport.MigrationConformanceIgnoredReferenceParentResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "ignored_reference_parents"
    repo OfficeGraph.Repo
    migration_ignore_attributes [:scope_id]
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :scope_id, :uuid, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceIgnoredReferenceChildResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "ignored_reference_children"
    repo OfficeGraph.Repo
    migration_ignore_attributes [:scope_id]

    references do
      reference :parent do
        name "ignored_reference_children_parent_fkey"
        index? true
        match_with scope_id: :scope_id
      end
    end
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :parent_id, :uuid, allow_nil?: false
    attribute :scope_id, :uuid, allow_nil?: false
  end

  relationships do
    belongs_to :parent,
               OfficeGraph.TestSupport.MigrationConformanceIgnoredReferenceParentResource do
      source_attribute :parent_id
      destination_attribute :id
      define_attribute? false
      allow_nil? false
    end
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceIgnoredDestinationParentResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "ignored_destination_parents"
    repo OfficeGraph.Repo
    migration_ignore_attributes [:id]
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :name, :string, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceIgnoredDestinationChildResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "ignored_destination_children"
    repo OfficeGraph.Repo

    references do
      reference :parent do
        name "ignored_destination_children_parent_fkey"
        index? true
      end
    end
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :parent_id, :uuid, allow_nil?: false
  end

  relationships do
    belongs_to :parent,
               OfficeGraph.TestSupport.MigrationConformanceIgnoredDestinationParentResource do
      source_attribute :parent_id
      destination_attribute :id
      define_attribute? false
      allow_nil? false
    end
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceIgnoredSourceChildResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "ignored_source_children"
    repo OfficeGraph.Repo
    migration_ignore_attributes [:parent_id]

    references do
      reference :parent do
        name "ignored_source_children_parent_fkey"
        index? true
      end
    end
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :parent_id, :uuid, allow_nil?: false
  end

  relationships do
    belongs_to :parent,
               OfficeGraph.TestSupport.MigrationConformanceIgnoredReferenceParentResource do
      source_attribute :parent_id
      destination_attribute :id
      define_attribute? false
      allow_nil? false
    end
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

defmodule OfficeGraph.TestSupport.MigrationConformanceSmallintResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  resource do
    require_primary_key? false
  end

  postgres do
    table "small_scores"
    repo OfficeGraph.Repo
    migration_types score: :smallint, alias_score: :int2
  end

  attributes do
    attribute :score, :integer, allow_nil?: false
    attribute :alias_score, :integer, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceObjectIdentifierResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  resource do
    require_primary_key? false
  end

  postgres do
    table "catalog_references"
    repo OfficeGraph.Repo

    migration_types object_id: :oid,
                    relation_ref: :regclass,
                    namespace_ref: :regnamespace,
                    transaction_id: :xid8,
                    tuple_id: :tid
  end

  attributes do
    attribute :object_id, :integer, allow_nil?: false
    attribute :relation_ref, :integer, allow_nil?: false
    attribute :namespace_ref, :integer, allow_nil?: false
    attribute :transaction_id, :integer, allow_nil?: false
    attribute :tuple_id, :string, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceCitextResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  resource do
    require_primary_key? false
  end

  postgres do
    table "citext_examples"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :label, :ci_string, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceLiteralResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  resource do
    require_primary_key? false
  end

  postgres do
    table "literal_examples"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :label, :string, allow_nil?: false, default: "a b"
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceLiteralDefaultsResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  resource do
    require_primary_key? false
  end

  postgres do
    table "literal_defaults"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :settings, :map, allow_nil?: false, default: %{}
    attribute :naive_at, :naive_datetime, allow_nil?: false
    attribute :utc_at, :utc_datetime, allow_nil?: false
    attribute :local_time, :time, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceCustomTypeResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  resource do
    require_primary_key? false
  end

  postgres do
    table "review_items"
    repo OfficeGraph.Repo
    migration_types status: :review_status
  end

  attributes do
    attribute :status, :string, allow_nil?: false, default: "pending"
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceQuotedCustomTypeResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  resource do
    require_primary_key? false
  end

  postgres do
    table "Typed Reviews"
    schema "Audit Space"
    repo OfficeGraph.Repo
    migration_types status: :review_status
  end

  attributes do
    attribute :status, :string, allow_nil?: false, default: "pending"
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
        match_type :simple
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

defmodule OfficeGraph.TestSupport.MigrationConformanceQuotedCommaParentResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "quoted_comma_parents"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :uuid, source: :"tenant,id", primary_key?: true, allow_nil?: false
    attribute :scope_id, :uuid, source: :parent_scope, allow_nil?: false
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceQuotedCommaChildResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "quoted_comma_children"
    repo OfficeGraph.Repo

    references do
      reference :parent do
        name "quoted_comma_children_parent_fkey"
        match_with scope_id: :scope_id
      end
    end
  end

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :parent_id, :uuid, source: :"parent,id", allow_nil?: false
    attribute :scope_id, :uuid, source: :child_scope, allow_nil?: false
  end

  relationships do
    belongs_to :parent,
               OfficeGraph.TestSupport.MigrationConformanceQuotedCommaParentResource do
      source_attribute :parent_id
      destination_attribute :id
      define_attribute? false
      allow_nil? false
    end
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceUtf8GeneratedNameResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "éééééééééééééééééééééééééééééé"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :integer,
      primary_key?: true,
      allow_nil?: false,
      generated?: true
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceApostropheSequenceResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "people's"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :integer,
      primary_key?: true,
      allow_nil?: false,
      generated?: true
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceQuotedResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "Review Items"
    schema "Audit Space"
    repo OfficeGraph.Repo
  end

  attributes do
    attribute :id, :uuid,
      source: :"External ID",
      primary_key?: true,
      allow_nil?: false

    attribute :label, :string, source: :"Display Label", allow_nil?: false
  end

  identities do
    identity :unique_label, [:label]
  end
end

defmodule OfficeGraph.TestSupport.MigrationConformanceQuotedChildResource do
  @moduledoc false

  use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

  postgres do
    table "Quoted Children"
    schema "Audit Space"
    repo OfficeGraph.Repo

    references do
      reference :parent do
        name "Quoted Children Parent FK"
        index? true
      end
    end
  end

  attributes do
    attribute :id, :uuid, source: :"Child ID", primary_key?: true, allow_nil?: false
    attribute :parent_id, :uuid, source: :"Parent ID", allow_nil?: false
  end

  relationships do
    belongs_to :parent, OfficeGraph.TestSupport.MigrationConformanceQuotedResource do
      source_attribute :parent_id
      destination_attribute :id
      define_attribute? false
      allow_nil? false
    end
  end
end
