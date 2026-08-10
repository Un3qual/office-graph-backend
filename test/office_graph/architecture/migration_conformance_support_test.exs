defmodule OfficeGraph.Architecture.MigrationConformanceSupportTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.TestSupport.MigrationConformanceSupport

  test "parses terminal schema dump object classes" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
      CREATE TABLE public.parents (
          id uuid NOT NULL,
          name text NOT NULL
      );
      CREATE TABLE public.children (
          id uuid NOT NULL,
          parent_id uuid NOT NULL
      );
      CREATE SEQUENCE public.unexpected_seq
          START WITH 1;
      CREATE VIEW public.read_model AS
       SELECT parents.id
         FROM public.parents;
      CREATE MATERIALIZED VIEW public.cached_model AS
       SELECT children.id
         FROM public.children;
      CREATE FUNCTION public.touch_child() RETURNS trigger
          LANGUAGE plpgsql
          AS $$ BEGIN RETURN NEW; END $$;
      CREATE TRIGGER touch_child BEFORE UPDATE ON public.children FOR EACH ROW EXECUTE FUNCTION public.touch_child();
      CREATE POLICY child_policy ON public.children USING (true);
      GRANT SELECT ON TABLE public.children TO readonly;
      CREATE UNIQUE INDEX children_parent_id_index ON public.children USING btree (parent_id);
      ALTER TABLE ONLY public.parents ADD CONSTRAINT parents_pkey PRIMARY KEY (id);
      ALTER TABLE ONLY public.children ADD CONSTRAINT children_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.parents(id);
      """)

    assert inventory.tables == MapSet.new(["children", "parents"])

    assert inventory.columns ==
             MapSet.new([
               {"children", "id", "uuid NOT NULL"},
               {"children", "parent_id", "uuid NOT NULL"},
               {"parents", "id", "uuid NOT NULL"},
               {"parents", "name", "text NOT NULL"}
             ])

    assert inventory.primary_keys == MapSet.new([{"parents", "parents_pkey"}])
    assert inventory.foreign_keys == [{"children", "parent_id", "parents", "id"}]

    assert inventory.indexes ==
             MapSet.new([
               {"children", "children_parent_id_index", "UNIQUE USING btree (parent_id)"}
             ])

    assert inventory.sequences == MapSet.new(["unexpected_seq"])
    assert inventory.views == MapSet.new(["read_model"])
    assert inventory.materialized_views == MapSet.new(["cached_model"])
    assert inventory.routines == MapSet.new(["touch_child"])
    assert inventory.triggers == MapSet.new(["touch_child ON children"])
    assert inventory.policies == MapSet.new(["child_policy ON children"])
    assert inventory.grants == MapSet.new(["children"])
    assert inventory.extensions == MapSet.new(["plpgsql"])
  end

  test "resource table identities preserve non-public schema prefixes" do
    resources = %{
      "children" => {nil, __MODULE__.PublicResource},
      "audit.events" => {nil, __MODULE__.AuditResource}
    }

    assert MigrationConformanceSupport.resource_table_identities(resources) == [
             "audit.events",
             "children"
           ]
  end

  test "foreign-key conformance rejects unresolved project attributes" do
    inventory = %{
      foreign_keys: [
        {"graph_items", "review_only_unmapped_attribute", "graph_items", "id"}
      ]
    }

    assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
             %{"graph_items" => {nil, OfficeGraph.WorkGraph.GraphItem}},
             inventory
           ) == [
             "graph_items.review_only_unmapped_attribute references graph_items.id without a matching belongs_to"
           ]
  end

  test "foreign-key conformance rejects an unresolved destination table" do
    inventory = %{
      foreign_keys: [{"graph_items", "organization_id", "unowned_records", "id"}]
    }

    assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
             %{"graph_items" => {nil, OfficeGraph.WorkGraph.GraphItem}},
             inventory
           ) == [
             "graph_items.organization_id references unowned_records.id without a matching belongs_to"
           ]
  end

  test "terminal errors reject unexpected project columns constraints and indexes" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.graph_items (
          id uuid DEFAULT uuidv7() NOT NULL,
          resource_type text NOT NULL,
          resource_id uuid NOT NULL,
          title text NOT NULL,
          inserted_at timestamp without time zone NOT NULL,
          updated_at timestamp without time zone NOT NULL,
          organization_id uuid NOT NULL,
          workspace_id uuid NOT NULL,
          rogue text
      );
      CREATE UNIQUE INDEX graph_items_unique_resource_index ON public.graph_items USING btree (resource_type, resource_id);
      CREATE INDEX graph_items_scope_id_index ON public.graph_items USING btree (organization_id, workspace_id, id);
      CREATE INDEX graph_items_rogue_index ON public.graph_items USING btree (rogue);
      ALTER TABLE ONLY public.graph_items ADD CONSTRAINT graph_items_pkey PRIMARY KEY (id);
      ALTER TABLE ONLY public.graph_items ADD CONSTRAINT graph_items_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organizations(id);
      ALTER TABLE ONLY public.graph_items ADD CONSTRAINT graph_items_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id);
      ALTER TABLE ONLY public.graph_items ADD CONSTRAINT graph_items_rogue_check CHECK ((rogue <> ''::text));
      """)

    errors =
      MigrationConformanceSupport.terminal_database_errors(
        %{"graph_items" => {nil, OfficeGraph.WorkGraph.GraphItem}},
        inventory
      )

    assert "unexpected project column graph_items.rogue" in errors
    assert "unexpected project constraint graph_items.graph_items_rogue_check" in errors
    assert "unexpected project index graph_items_rogue_index ON graph_items" in errors
  end

  test "terminal errors reject incompatible column and index definitions" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.shapes (
          id text NOT NULL,
          name text DEFAULT 'wrong'::text NOT NULL
      );
      CREATE INDEX shapes_unique_name_index ON public.shapes USING hash (id);
      ALTER TABLE ONLY public.shapes ADD CONSTRAINT shapes_pkey PRIMARY KEY (name);
      """)

    errors =
      MigrationConformanceSupport.terminal_database_errors(
        %{
          "shapes" => {nil, OfficeGraph.TestSupport.MigrationConformanceShapeResource}
        },
        inventory
      )

    assert "column definition mismatch for shapes.id: expected uuid NOT NULL, got text NOT NULL" in errors

    assert "column definition mismatch for shapes.name: expected text NOT NULL, got text DEFAULT 'wrong'::text NOT NULL" in errors

    assert "constraint definition mismatch for shapes_pkey ON shapes: expected PRIMARY KEY (id), got PRIMARY KEY (name)" in errors

    assert "index definition mismatch for shapes_unique_name_index ON shapes: expected UNIQUE USING btree (name), got USING hash (id)" in errors
  end

  test "terminal definitions preserve schema-like text inside SQL literals" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.literal_examples (
          id uuid NOT NULL,
          qualified_text text DEFAULT 'public.user'::text NOT NULL,
          unqualified_text text DEFAULT 'user'::text NOT NULL
      );
      """)

    assert {"literal_examples", "qualified_text", "text DEFAULT 'public.user'::text NOT NULL"} in inventory.columns

    assert {"literal_examples", "unqualified_text", "text DEFAULT 'user'::text NOT NULL"} in inventory.columns
  end

  test "terminal errors accept declarative generated integer sequences" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.sequence_examples (
          id bigint NOT NULL
      );
      CREATE SEQUENCE public.sequence_examples_id_seq
          START WITH 1;
      ALTER TABLE ONLY public.sequence_examples ALTER COLUMN id SET DEFAULT nextval('public.sequence_examples_id_seq'::regclass);
      ALTER TABLE ONLY public.sequence_examples ADD CONSTRAINT sequence_examples_pkey PRIMARY KEY (id);
      """)

    assert {"sequence_examples", "id",
            "bigint DEFAULT nextval('sequence_examples_id_seq'::regclass) NOT NULL"} in inventory.columns

    assert MigrationConformanceSupport.terminal_database_errors(
             %{
               "sequence_examples" =>
                 {nil, OfficeGraph.TestSupport.MigrationConformanceSequenceResource}
             },
             inventory
           ) == []
  end

  test "terminal errors reject generated integer sequences without a column default" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.sequence_examples (
          id bigint NOT NULL
      );
      CREATE SEQUENCE public.sequence_examples_id_seq
          START WITH 1;
      ALTER TABLE ONLY public.sequence_examples ADD CONSTRAINT sequence_examples_pkey PRIMARY KEY (id);
      """)

    assert "column definition mismatch for sequence_examples.id: expected bigint DEFAULT nextval('sequence_examples_id_seq'::regclass) NOT NULL, got bigint NOT NULL" in MigrationConformanceSupport.terminal_database_errors(
             %{
               "sequence_examples" =>
                 {nil, OfficeGraph.TestSupport.MigrationConformanceSequenceResource}
             },
             inventory
           )
  end

  test "terminal constraints resolve match_with attributes to physical columns" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.composite_parents (
          parent_id uuid NOT NULL,
          parent_scope uuid NOT NULL
      );
      CREATE TABLE public.composite_children (
          id uuid NOT NULL,
          linked_parent_id uuid NOT NULL,
          child_scope uuid NOT NULL
      );
      ALTER TABLE ONLY public.composite_parents ADD CONSTRAINT composite_parents_pkey PRIMARY KEY (parent_id);
      ALTER TABLE ONLY public.composite_children ADD CONSTRAINT composite_children_pkey PRIMARY KEY (id);
      ALTER TABLE ONLY public.composite_children ADD CONSTRAINT composite_children_parent_fkey FOREIGN KEY (linked_parent_id, child_scope) REFERENCES public.composite_parents(parent_id, parent_scope);
      """)

    errors =
      MigrationConformanceSupport.terminal_database_errors(
        %{
          "composite_children" =>
            {nil, OfficeGraph.TestSupport.MigrationConformanceCompositeChildResource},
          "composite_parents" =>
            {nil, OfficeGraph.TestSupport.MigrationConformanceCompositeParentResource}
        },
        inventory
      )

    refute Enum.any?(errors, &String.contains?(&1, "composite_children_parent_fkey"))
    refute Enum.any?(errors, &String.contains?(&1, "without a matching belongs_to"))
  end

  defmodule PublicResource do
    use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

    postgres do
      table "children"
      repo OfficeGraph.Repo
    end
  end

  defmodule AuditResource do
    use Ash.Resource, domain: nil, data_layer: AshPostgres.DataLayer

    postgres do
      table "events"
      schema "audit"
      repo OfficeGraph.Repo
    end
  end
end
