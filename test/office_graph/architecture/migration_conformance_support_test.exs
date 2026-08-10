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
               {"children", "id"},
               {"children", "parent_id"},
               {"parents", "id"},
               {"parents", "name"}
             ])

    assert inventory.primary_keys == MapSet.new([{"parents", "parents_pkey"}])
    assert inventory.foreign_keys == [{"children", "parent_id", "parents", "id"}]
    assert inventory.indexes == MapSet.new(["children_parent_id_index ON children"])
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
      "events" => {nil, __MODULE__.AuditResource}
    }

    assert MigrationConformanceSupport.resource_table_identities(resources) == [
             "audit.events",
             "children"
           ]
  end

  test "terminal errors reject unexpected project columns constraints and indexes" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.graph_items (
          id uuid NOT NULL,
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

    assert MigrationConformanceSupport.terminal_database_errors(
             %{"graph_items" => {nil, OfficeGraph.WorkGraph.GraphItem}},
             inventory
           ) == [
             "unexpected project column graph_items.rogue",
             "unexpected project constraint graph_items.graph_items_rogue_check",
             "unexpected project index graph_items_rogue_index ON graph_items"
           ]
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
