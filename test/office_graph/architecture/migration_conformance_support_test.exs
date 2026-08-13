defmodule OfficeGraph.Architecture.MigrationConformanceSupportTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.TestSupport.MigrationConformanceSupport
  alias OfficeGraph.TestSupport.PostgresDump

  @framework_presence_errors MapSet.new([
                               "missing framework enum oban_job_state",
                               "missing framework sequence oban_jobs_id_seq",
                               "missing framework table oban_jobs",
                               "missing framework table oban_peers",
                               "missing framework table schema_migrations"
                             ])

  test "Docker pg_dump fallback is limited to loopback database hosts" do
    for host <- ["localhost", "127.0.0.1", "::1"] do
      assert MigrationConformanceSupport.docker_fallback_allowed?(host)
    end

    for host <- ["db.internal", "postgres", "192.0.2.10", nil] do
      refute MigrationConformanceSupport.docker_fallback_allowed?(host)
    end
  end

  test "Docker pg_dump fallback keeps the password out of process arguments" do
    password = "not-visible-in-argv"

    {arguments, env} =
      MigrationConformanceSupport.docker_pg_dump_invocation("container-id",
        username: "postgres",
        password: password,
        database: "office_graph_test"
      )

    refute Enum.any?(arguments, &String.contains?(&1, password))
    assert ["exec", "-e", "PGPASSWORD", "container-id", "pg_dump" | _rest] = arguments
    assert env == [{"PGPASSWORD", password}]
  end

  test "parenthesized SQL keeps parentheses inside dollar-quoted strings" do
    assert PostgresDump.take_parenthesized(~S|($$text ) and ($$) trailing|) ==
             {~S|$$text ) and ($$|, " trailing"}

    assert PostgresDump.take_parenthesized(~S|($body$text ) and ($body$) trailing|) ==
             {~S|$body$text ) and ($body$|, " trailing"}
  end

  test "PostgreSQL identifiers and dollar-quote tags accept Unicode letters" do
    assert PostgresDump.normalize_identifier("名字") == "名字"
    assert PostgresDump.configured_identifier("δelta") == "δelta"

    assert PostgresDump.split_statements("""
           CREATE FUNCTION public.unicode_body() RETURNS integer
           LANGUAGE plpgsql AS $函数$ BEGIN; RETURN 1; END $函数$;
           CREATE TABLE public.after_unicode_body (id uuid);
           """)
           |> length() == 2
  end

  test "dollar-quote-shaped identifier suffixes stay in the identifier token" do
    assert PostgresDump.split_statements(
             "CREATE TABLE object$tag$ (id integer); CREATE TABLE later (id integer);"
           ) == [
             "CREATE TABLE object$tag$ (id integer);",
             "CREATE TABLE later (id integer);"
           ]

    assert PostgresDump.split_once_outside_quotes("object$tag$ ON target", " ON ") ==
             {"object$tag$", "target"}

    assert PostgresDump.normalize_definition("object$tag$   text") == "object$tag$ text"

    assert PostgresDump.take_parenthesized("(object$tag$, next) trailing") ==
             {"object$tag$, next", " trailing"}
  end

  test "SQL keywords do not split identifiers" do
    assert PostgresDump.split_once_outside_quotes(
             "fooCONSTRAINT bar",
             "CONSTRAINT "
           ) == nil

    assert PostgresDump.split_once_outside_quotes(
             "foo CONSTRAINT bar",
             "CONSTRAINT "
           ) == {"foo ", "bar"}
  end

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
      CREATE CONSTRAINT TRIGGER deferred_touch_child AFTER UPDATE ON public.children DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.touch_child();
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
    assert inventory.routines == MapSet.new(["touch_child()"])

    assert inventory.triggers ==
             MapSet.new(["deferred_touch_child ON children", "touch_child ON children"])

    assert inventory.terminal_objects
           |> Enum.filter(&(elem(&1, 0) == "trigger"))
           |> Enum.map(&elem(&1, 1))
           |> Enum.sort() == ["deferred_touch_child ON children", "touch_child ON children"]

    assert inventory.policies == MapSet.new(["child_policy ON children"])
    assert inventory.grants == MapSet.new(["SELECT ON TABLE children TO readonly"])
    assert inventory.extensions == MapSet.new(["plpgsql"])
  end

  test "terminal inventory compares project-owned schemas" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE SCHEMA public;
      CREATE SCHEMA audit;
      CREATE TABLE audit.events (
          id uuid NOT NULL
      );
      """)

    assert inventory.schemas == MapSet.new(["audit", "public"])

    errors =
      inventory
      |> synthetic_terminal_errors(%{"audit.events" => {nil, __MODULE__.AuditResource}})
      |> without_framework_presence_errors()

    refute Enum.any?(errors, &String.contains?(&1, "schema audit"))
    refute Enum.any?(errors, &String.contains?(&1, "schema public"))

    unexpected = MigrationConformanceSupport.parse_dump("CREATE SCHEMA shadow;")

    assert "unexpected project schema shadow" in (unexpected
                                                  |> synthetic_terminal_errors(%{})
                                                  |> without_framework_presence_errors())
  end

  test "terminal inventory fails closed on unknown project-owned object DDL" do
    inventory =
      MigrationConformanceSupport.parse_dump("CREATE DOMAIN public.account_id AS uuid;")

    assert inventory.unrecognized_ddl == MapSet.new(["CREATE DOMAIN public.account_id AS uuid"])

    errors =
      inventory
      |> synthetic_terminal_errors(%{})
      |> without_framework_presence_errors()

    assert "unrecognized project DDL CREATE DOMAIN public.account_id AS uuid" in errors
  end

  test "terminal inventory pins the Oban job-state enum labels and order" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TYPE public.oban_job_state AS ENUM (
          'available',
          'suspended',
          'scheduled',
          'executing',
          'retryable',
          'completed',
          'discarded',
          'cancelled'
      );
      """)

    assert inventory.enums == %{
             "oban_job_state" =>
               "'available', 'suspended', 'scheduled', 'executing', 'retryable', 'completed', 'discarded', 'cancelled'"
           }

    refute Enum.any?(
             MigrationConformanceSupport.terminal_database_errors(%{}, inventory, []),
             &String.contains?(&1, "oban_job_state")
           )

    drifted =
      MigrationConformanceSupport.parse_dump("""
      CREATE TYPE public.oban_job_state AS ENUM (
          'available',
          'scheduled',
          'suspended',
          'executing',
          'retryable',
          'completed',
          'discarded',
          'cancelled'
      );
      """)

    assert "enum definition mismatch for framework enum oban_job_state" in MigrationConformanceSupport.terminal_database_errors(
             %{},
             drifted,
             []
           )
  end

  test "terminal inventory requires approval for non-framework enums" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TYPE public.review_state AS ENUM ('open', 'closed');
      """)

    assert Enum.any?(
             MigrationConformanceSupport.terminal_database_errors(%{}, inventory, []),
             &(&1 == "unexpected project enum review_state")
           )
  end

  test "terminal approvals match exact stored-object definitions" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE FUNCTION public.touch_child() RETURNS trigger
          LANGUAGE plpgsql
          AS $$ BEGIN
        PERFORM pg_notify('children', 'changed');
        RETURN NEW;
      END $$;
      """)

    [{"routine", "touch_child()", fingerprint}] = Enum.to_list(inventory.terminal_objects)

    approval = %{
      "class" => "routine",
      "identity" => "touch_child()",
      "fingerprint" => fingerprint
    }

    assert inventory
           |> synthetic_terminal_errors(%{}, [approval])
           |> without_framework_presence_errors() == []

    changed_approval =
      Map.put(
        approval,
        "fingerprint",
        "sha256:0000000000000000000000000000000000000000000000000000000000000000"
      )

    assert inventory
           |> synthetic_terminal_errors(%{}, [changed_approval])
           |> without_framework_presence_errors() ==
             [
               "terminal definition mismatch for approved project routine touch_child()"
             ]
  end

  test "view approvals fingerprint column defaults with the view definition" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE VIEW public.review_queue AS SELECT NULL::text AS state;
      ALTER VIEW public.review_queue ALTER COLUMN state SET DEFAULT 'pending'::text;
      CREATE VIEW public.review_archive AS SELECT NULL::text AS state;
      ALTER TABLE ONLY public.review_archive ALTER COLUMN state SET DEFAULT 'archived'::text;
      """)

    approvals =
      Enum.map(inventory.terminal_objects, fn {class, identity, fingerprint} ->
        %{"class" => class, "identity" => identity, "fingerprint" => fingerprint}
      end)

    assert Enum.count(approvals, &(&1["class"] == "view" and &1["identity"] == "review_queue")) ==
             2

    assert Enum.count(
             approvals,
             &(&1["class"] == "view" and &1["identity"] == "review_archive")
           ) == 2

    assert inventory
           |> synthetic_terminal_errors(%{}, approvals)
           |> without_framework_presence_errors() == []

    [create_approval, _default_approval] =
      Enum.filter(approvals, &(&1["identity"] == "review_queue"))

    other_approvals = Enum.reject(approvals, &(&1["identity"] == "review_queue"))

    assert "terminal definition mismatch for approved project view review_queue" in MigrationConformanceSupport.terminal_database_errors(
             %{},
             inventory,
             [create_approval | other_approvals]
           )
  end

  test "materialized-view indexes require independent exact terminal approval" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE MATERIALIZED VIEW public.cached_children AS
       SELECT children.id
         FROM public.children;
      CREATE UNIQUE INDEX cached_children_id_index ON public.cached_children USING btree (id);
      """)

    approvals =
      inventory.terminal_objects
      |> Enum.map(fn {class, identity, fingerprint} ->
        %{"class" => class, "identity" => identity, "fingerprint" => fingerprint}
      end)

    view_approval = Enum.find(approvals, &(&1["class"] == "materialized view"))

    assert "unexpected project materialized view index cached_children_id_index ON cached_children" in MigrationConformanceSupport.terminal_database_errors(
             %{},
             inventory,
             [view_approval]
           )

    assert inventory
           |> synthetic_terminal_errors(%{}, approvals)
           |> without_framework_presence_errors() == []
  end

  test "inventories event triggers, trigger firing modes, and row-level-security state" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE EVENT TRIGGER audit_ddl ON ddl_command_end EXECUTE FUNCTION public.audit_ddl();
      ALTER EVENT TRIGGER audit_ddl ENABLE ALWAYS;
      CREATE TRIGGER touch_child BEFORE UPDATE ON public.children FOR EACH ROW EXECUTE FUNCTION public.touch_child();
      ALTER TABLE ONLY public.children DISABLE TRIGGER touch_child;
      ALTER TABLE public.children ENABLE ROW LEVEL SECURITY;
      ALTER TABLE ONLY public.children FORCE ROW LEVEL SECURITY;
      """)

    assert inventory.triggers ==
             MapSet.new(["audit_ddl ON DATABASE", "touch_child ON children"])

    assert inventory.rls_states == MapSet.new(["children"])

    terminal_identities =
      inventory.terminal_objects
      |> Enum.map(fn {class, identity, fingerprint} ->
        assert String.starts_with?(fingerprint, "sha256:")
        {class, identity}
      end)
      |> Enum.sort()

    assert terminal_identities == [
             {"RLS state", "children"},
             {"RLS state", "children"},
             {"trigger", "audit_ddl ON DATABASE"},
             {"trigger", "audit_ddl ON DATABASE"},
             {"trigger", "touch_child ON children"},
             {"trigger", "touch_child ON children"}
           ]
  end

  test "inventories default-privilege grants" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      ALTER DEFAULT PRIVILEGES FOR ROLE app IN SCHEMA public GRANT SELECT ON TABLES TO readonly;
      """)

    identity =
      "ALTER DEFAULT PRIVILEGES FOR ROLE app IN SCHEMA public GRANT SELECT ON TABLES TO readonly"

    assert inventory.grants == MapSet.new([identity])

    assert [{"grant", ^identity, "sha256:" <> _hash}] =
             Enum.to_list(inventory.terminal_objects)
  end

  test "inventories grants with quoted object and role identities" do
    inventory =
      MigrationConformanceSupport.parse_dump(~S'''
      GRANT SELECT ON TABLE public."review items" TO "read only";
      ''')

    identity = ~s|SELECT ON TABLE "review items" TO "read only"|

    assert inventory.grants == MapSet.new([identity])

    assert [{"grant", ^identity, "sha256:" <> _hash}] =
             Enum.to_list(inventory.terminal_objects)
  end

  test "terminal errors exempt only exact Oban-owned objects" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.oban_jobs (
          id bigint NOT NULL,
          injected text
      );
      CREATE SEQUENCE public.oban_jobs_id_seq
          START WITH 1;
      CREATE INDEX injected_oban_index ON public.oban_jobs USING btree (injected);
      ALTER TABLE ONLY public.oban_jobs ADD CONSTRAINT injected_oban_check CHECK ((injected <> ''::text));
      CREATE TABLE public.oban_shadow (
          id uuid NOT NULL
      );
      """)

    errors = MigrationConformanceSupport.terminal_database_errors(%{}, inventory, [])

    assert "unexpected project table oban_shadow" in errors
    assert "unexpected project column oban_jobs.injected" in errors
    assert "unexpected project constraint oban_jobs.injected_oban_check" in errors
    assert "unexpected project index injected_oban_index ON oban_jobs" in errors
    refute "unexpected project table oban_jobs" in errors
    refute "unexpected project sequence oban_jobs_id_seq" in errors
  end

  test "terminal errors require every configured framework object" do
    errors =
      MigrationConformanceSupport.terminal_database_errors(
        %{},
        MigrationConformanceSupport.parse_dump(""),
        []
      )

    assert "missing framework table oban_jobs" in errors
    assert "missing framework table oban_peers" in errors
    assert "missing framework table schema_migrations" in errors
    assert "missing framework sequence oban_jobs_id_seq" in errors
  end

  test "terminal errors do not exempt arbitrary triggers on framework tables" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TRIGGER injected_oban_trigger BEFORE UPDATE ON public.oban_jobs FOR EACH ROW EXECUTE FUNCTION public.injected_oban_trigger();
      """)

    assert "unexpected project trigger injected_oban_trigger ON oban_jobs" in MigrationConformanceSupport.terminal_database_errors(
             %{},
             inventory,
             []
           )
  end

  test "terminal inventory preserves quoted object identities" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE VIEW public."review view" AS SELECT 1;
      CREATE FUNCTION public."do thing"() RETURNS integer LANGUAGE sql AS $$ SELECT 1 $$;
      CREATE POLICY "allow users" ON public."review items" USING (true);
      CREATE TRIGGER "touch items" BEFORE UPDATE ON public."review items" FOR EACH ROW EXECUTE FUNCTION public."do thing"();
      ALTER TABLE ONLY public."review items" DISABLE TRIGGER "touch items";
      ALTER TABLE public."review items" ENABLE ROW LEVEL SECURITY;
      """)

    assert inventory.views == MapSet.new([~s("review view")])
    assert inventory.routines == MapSet.new([~s|"do thing"()|])
    assert inventory.policies == MapSet.new([~s|"allow users" ON "review items"|])
    assert inventory.triggers == MapSet.new([~s|"touch items" ON "review items"|])
    assert inventory.rls_states == MapSet.new([~s|"review items"|])

    assert inventory.terminal_objects
           |> Enum.map(fn {class, identity, _fingerprint} -> {class, identity} end)
           |> Enum.sort() == [
             {"RLS policy", ~s|"allow users" ON "review items"|},
             {"RLS state", ~s|"review items"|},
             {"routine", ~s|"do thing"()|},
             {"trigger", ~s|"touch items" ON "review items"|},
             {"trigger", ~s|"touch items" ON "review items"|},
             {"view", ~s|"review view"|}
           ]
  end

  test "terminal inventory treats unlogged tables as owned tables" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE UNLOGGED TABLE public.shadow_records (
          id uuid NOT NULL
      );
      """)

    assert inventory.tables == MapSet.new(["shadow_records"])
    assert inventory.columns == MapSet.new([{"shadow_records", "id", "uuid NOT NULL"}])

    assert "unexpected project table shadow_records" in MigrationConformanceSupport.terminal_database_errors(
             %{},
             inventory,
             []
           )
  end

  test "terminal errors reject relation-kind drift for an Ash-owned table" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE UNLOGGED TABLE public.shapes (
          id uuid NOT NULL,
          name text NOT NULL
      );
      CREATE UNIQUE INDEX shapes_unique_name_index ON public.shapes USING btree (name);
      ALTER TABLE ONLY public.shapes ADD CONSTRAINT shapes_pkey PRIMARY KEY (id);
      """)

    assert inventory.relations == %{"shapes" => :unlogged}

    assert "relation kind mismatch for Ash-owned table shapes: expected regular, got unlogged" in MigrationConformanceSupport.terminal_database_errors(
             %{
               "shapes" => {nil, OfficeGraph.TestSupport.MigrationConformanceShapeResource}
             },
             inventory,
             []
           )
  end

  test "terminal errors reject partitioned parents and attached partition children" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.shapes (
          id uuid NOT NULL,
          name text NOT NULL
      ) PARTITION BY HASH (id);
      CREATE TABLE public.shape_partition (
          id uuid NOT NULL,
          name text NOT NULL
      );
      ALTER TABLE ONLY public.shapes ATTACH PARTITION public.shape_partition FOR VALUES WITH (modulus 2, remainder 0);
      CREATE UNIQUE INDEX shapes_unique_name_index ON public.shapes USING btree (name);
      ALTER TABLE ONLY public.shapes ADD CONSTRAINT shapes_pkey PRIMARY KEY (id);
      """)

    assert inventory.relations == %{
             "shape_partition" => :partition,
             "shapes" => :partitioned
           }

    errors =
      MigrationConformanceSupport.terminal_database_errors(
        %{
          "shape_partition" =>
            {nil, OfficeGraph.TestSupport.MigrationConformancePartitionShapeResource},
          "shapes" => {nil, OfficeGraph.TestSupport.MigrationConformanceShapeResource}
        },
        inventory,
        []
      )

    assert "relation kind mismatch for Ash-owned table shapes: expected regular, got partitioned" in errors

    assert "relation kind mismatch for Ash-owned table shape_partition: expected regular, got partition" in errors
  end

  test "terminal inventory treats imported foreign tables as owned tables" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE FOREIGN TABLE public.imported_accounts (
          id uuid NOT NULL,
          email text
      )
      SERVER upstream;
      """)

    assert inventory.tables == MapSet.new(["imported_accounts"])

    assert inventory.columns ==
             MapSet.new([
               {"imported_accounts", "email", "text"},
               {"imported_accounts", "id", "uuid NOT NULL"}
             ])

    assert "unexpected project table imported_accounts" in MigrationConformanceSupport.terminal_database_errors(
             %{},
             inventory,
             []
           )
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

  test "terminal comparison canonicalizes configured quoted resource identities" do
    inventory =
      MigrationConformanceSupport.parse_dump(~S'''
      CREATE TABLE "Audit Space"."Review Items" (
          "External ID" uuid CONSTRAINT "Review Items_External ID_not_null" NOT NULL,
          "Display Label" text NOT NULL
      );
      CREATE UNIQUE INDEX "Review Items_unique_label_index" ON "Audit Space"."Review Items" USING btree ("Display Label");
      ALTER TABLE ONLY "Audit Space"."Review Items" ADD CONSTRAINT "Review Items_pkey" PRIMARY KEY ("External ID");
      ''')

    resources = %{
      "Review Items" => {nil, OfficeGraph.TestSupport.MigrationConformanceQuotedResource}
    }

    assert MigrationConformanceSupport.resource_table_identities(resources) == [
             ~s|"Audit Space"."Review Items"|
           ]

    assert inventory
           |> synthetic_terminal_errors(resources, [])
           |> without_framework_presence_errors() == []
  end

  test "terminal comparison qualifies the AshPostgres citext extension type" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.citext_examples (
          label public.citext NOT NULL
      );
      """)

    resources = %{
      "citext_examples" => {nil, OfficeGraph.TestSupport.MigrationConformanceCitextResource}
    }

    assert inventory
           |> synthetic_terminal_errors(resources, [])
           |> without_framework_presence_errors() == []
  end

  test "terminal comparison canonicalizes quoted foreign-key and reference-index columns" do
    inventory =
      MigrationConformanceSupport.parse_dump(~S'''
      CREATE TABLE "Audit Space"."Review Items" (
          "External ID" uuid NOT NULL,
          "Display Label" text NOT NULL
      );
      CREATE UNIQUE INDEX "Review Items_unique_label_index" ON "Audit Space"."Review Items" USING btree ("Display Label");
      ALTER TABLE ONLY "Audit Space"."Review Items" ADD CONSTRAINT "Review Items_pkey" PRIMARY KEY ("External ID");
      CREATE TABLE "Audit Space"."Quoted Children" (
          "Child ID" uuid NOT NULL,
          "Parent ID" uuid NOT NULL
      );
      CREATE INDEX "Quoted Children_Parent ID_index" ON "Audit Space"."Quoted Children" USING btree ("Parent ID");
      ALTER TABLE ONLY "Audit Space"."Quoted Children" ADD CONSTRAINT "Quoted Children_pkey" PRIMARY KEY ("Child ID");
      ALTER TABLE ONLY "Audit Space"."Quoted Children" ADD CONSTRAINT "Quoted Children Parent FK" FOREIGN KEY ("Parent ID") REFERENCES "Audit Space"."Review Items"("External ID");
      ''')

    resources = %{
      "Quoted Children" => {nil, OfficeGraph.TestSupport.MigrationConformanceQuotedChildResource},
      "Review Items" => {nil, OfficeGraph.TestSupport.MigrationConformanceQuotedResource}
    }

    assert inventory
           |> synthetic_terminal_errors(resources, [])
           |> without_framework_presence_errors() == []
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

  test "terminal definitions preserve significant whitespace inside SQL literals" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.literal_examples (
          label text DEFAULT 'a  b'::text NOT NULL
      );
      """)

    assert {"literal_examples", "label", "text DEFAULT 'a  b'::text NOT NULL"} in inventory.columns

    assert "column definition mismatch for literal_examples.label: expected text DEFAULT 'a b'::text NOT NULL, got text DEFAULT 'a  b'::text NOT NULL" in MigrationConformanceSupport.terminal_database_errors(
             %{
               "literal_examples" =>
                 {nil, OfficeGraph.TestSupport.MigrationConformanceLiteralResource}
             },
             inventory,
             []
           )
  end

  test "terminal errors preserve supported map defaults and non-usec temporal precision" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.literal_defaults (
          settings jsonb DEFAULT '{}'::jsonb NOT NULL,
          naive_at timestamp(0) without time zone NOT NULL,
          utc_at timestamp(0) without time zone NOT NULL,
          local_time time(0) without time zone NOT NULL
      );
      """)

    assert inventory
           |> synthetic_terminal_errors(%{
             "literal_defaults" =>
               {nil, OfficeGraph.TestSupport.MigrationConformanceLiteralDefaultsResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal definitions retain named not-null constraints" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.literal_examples (
          label text DEFAULT 'a b'::text CONSTRAINT label_required NOT NULL
      );
      """)

    assert {"literal_examples", "label",
            "text DEFAULT 'a b'::text CONSTRAINT label_required NOT NULL"} in inventory.columns

    assert Enum.any?(
             MigrationConformanceSupport.terminal_database_errors(
               %{
                 "literal_examples" =>
                   {nil, OfficeGraph.TestSupport.MigrationConformanceLiteralResource}
               },
               inventory,
               []
             ),
             &String.starts_with?(&1, "column definition mismatch for literal_examples.label:")
           )
  end

  test "quoted constraint remains a table column" do
    inventory =
      MigrationConformanceSupport.parse_dump(~S'''
      CREATE TABLE public.literal_examples (
          "constraint" text NOT NULL
      );
      ''')

    assert inventory.columns ==
             MapSet.new([{"literal_examples", "constraint", "text NOT NULL"}])
  end

  test "terminal definitions normalize only PostgreSQL-generated not-null names" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.literal_examples (
          label text DEFAULT 'a b'::text CONSTRAINT literal_examples_label_not_null NOT NULL
      );
      """)

    assert {"literal_examples", "label", "text DEFAULT 'a b'::text NOT NULL"} in inventory.columns

    assert inventory
           |> synthetic_terminal_errors(
             %{
               "literal_examples" =>
                 {nil, OfficeGraph.TestSupport.MigrationConformanceLiteralResource}
             },
             []
           )
           |> without_framework_presence_errors() == []
  end

  test "generated not-null names truncate only at UTF-8 codepoint boundaries" do
    table = String.duplicate("é", 30)
    column = String.duplicate("é", 30)
    generated_name = String.duplicate("é", 13) <> "_" <> String.duplicate("é", 13) <> "_not_null"

    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public."#{table}" (
          "#{column}" text CONSTRAINT "#{generated_name}" NOT NULL
      );
      """)

    assert inventory.columns ==
             MapSet.new([{table, column, "text NOT NULL"}])
  end

  test "terminal errors accept declarative generated integer sequences" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.sequence_examples (
          id bigint NOT NULL
      );
      CREATE SEQUENCE public.sequence_examples_id_seq
          AS bigint
          START WITH 1
          INCREMENT BY 1
          NO MINVALUE
          NO MAXVALUE
          CACHE 1
          NO CYCLE;
      ALTER SEQUENCE public.sequence_examples_id_seq OWNED BY public.sequence_examples.id;
      ALTER TABLE ONLY public.sequence_examples ALTER COLUMN id SET DEFAULT nextval('public.sequence_examples_id_seq'::regclass);
      ALTER TABLE ONLY public.sequence_examples ADD CONSTRAINT sequence_examples_pkey PRIMARY KEY (id);
      """)

    assert {"sequence_examples", "id",
            "bigint DEFAULT nextval('sequence_examples_id_seq'::regclass) NOT NULL"} in inventory.columns

    assert inventory
           |> synthetic_terminal_errors(%{
             "sequence_examples" =>
               {nil, OfficeGraph.TestSupport.MigrationConformanceSequenceResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal errors accept apostrophes in generated sequence regclass defaults" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public."people's" (
          id bigint DEFAULT nextval('public."people''s_id_seq"'::regclass) NOT NULL
      );
      CREATE SEQUENCE public."people's_id_seq"
          AS bigint
          START WITH 1
          INCREMENT BY 1
          NO MINVALUE
          NO MAXVALUE
          CACHE 1
          NO CYCLE;
      ALTER SEQUENCE public."people's_id_seq" OWNED BY public."people's".id;
      ALTER TABLE ONLY public."people's" ADD CONSTRAINT "people's_pkey" PRIMARY KEY (id);
      """)

    assert {"\"people's\"", "id",
            "bigint DEFAULT nextval('\"people''s_id_seq\"'::regclass) NOT NULL"} in inventory.columns

    assert inventory
           |> synthetic_terminal_errors(%{
             "\"people's\"" =>
               {nil, OfficeGraph.TestSupport.MigrationConformanceApostropheSequenceResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "all generated identifiers truncate by complete UTF-8 bytes" do
    table = "éééééééééééééééééééééééééééééé"
    generated_name = table <> "_id"

    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public."#{table}" (
          id bigint DEFAULT nextval('public."#{generated_name}"'::regclass) NOT NULL
      );
      CREATE SEQUENCE public."#{generated_name}"
          AS bigint
          START WITH 1
          INCREMENT BY 1
          NO MINVALUE
          NO MAXVALUE
          CACHE 1
          NO CYCLE;
      ALTER SEQUENCE public."#{generated_name}" OWNED BY public."#{table}".id;
      ALTER TABLE ONLY public."#{table}" ADD CONSTRAINT "#{table}_pk" PRIMARY KEY (id);
      """)

    assert inventory
           |> synthetic_terminal_errors(%{
             table => {nil, OfficeGraph.TestSupport.MigrationConformanceUtf8GeneratedNameResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal errors reject sequence definition drift" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.sequence_examples (
          id bigint NOT NULL
      );
      CREATE SEQUENCE public.sequence_examples_id_seq
          AS bigint
          START WITH 1
          INCREMENT BY 2
          NO MINVALUE
          NO MAXVALUE
          CACHE 1
          NO CYCLE;
      ALTER SEQUENCE public.sequence_examples_id_seq OWNED BY public.sequence_examples.id;
      ALTER TABLE ONLY public.sequence_examples ALTER COLUMN id SET DEFAULT nextval('public.sequence_examples_id_seq'::regclass);
      ALTER TABLE ONLY public.sequence_examples ADD CONSTRAINT sequence_examples_pkey PRIMARY KEY (id);
      """)

    assert "sequence definition mismatch for sequence_examples_id_seq" in MigrationConformanceSupport.terminal_database_errors(
             %{
               "sequence_examples" =>
                 {nil, OfficeGraph.TestSupport.MigrationConformanceSequenceResource}
             },
             inventory,
             []
           )
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

  test "terminal errors ignore sequences for migration-ignored generated attributes" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.ignored_sequence_examples (
          id uuid NOT NULL
      );
      ALTER TABLE ONLY public.ignored_sequence_examples ADD CONSTRAINT ignored_sequence_examples_pkey PRIMARY KEY (id);
      """)

    assert inventory
           |> synthetic_terminal_errors(%{
             "ignored_sequence_examples" =>
               {nil, OfficeGraph.TestSupport.MigrationConformanceIgnoredSequenceResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal errors omit migration-ignored primary-key attributes" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.ignored_primary_key_examples (
          name text NOT NULL
      );
      """)

    assert inventory
           |> synthetic_terminal_errors(%{
             "ignored_primary_key_examples" =>
               {nil, OfficeGraph.TestSupport.MigrationConformanceIgnoredPrimaryKeyResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal errors omit references whose match attributes are migration-ignored" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.ignored_reference_parents (
          id uuid NOT NULL
      );
      CREATE TABLE public.ignored_reference_children (
          id uuid NOT NULL,
          parent_id uuid NOT NULL
      );
      ALTER TABLE ONLY public.ignored_reference_parents ADD CONSTRAINT ignored_reference_parents_pkey PRIMARY KEY (id);
      ALTER TABLE ONLY public.ignored_reference_children ADD CONSTRAINT ignored_reference_children_pkey PRIMARY KEY (id);
      """)

    resources = %{
      "ignored_reference_parents" =>
        {nil, OfficeGraph.TestSupport.MigrationConformanceIgnoredReferenceParentResource},
      "ignored_reference_children" =>
        {nil, OfficeGraph.TestSupport.MigrationConformanceIgnoredReferenceChildResource}
    }

    assert inventory
           |> synthetic_terminal_errors(resources, [])
           |> without_framework_presence_errors() == []
  end

  test "terminal errors omit references with migration-ignored destination attributes" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.ignored_destination_parents (
          name text NOT NULL
      );
      CREATE TABLE public.ignored_destination_children (
          id uuid NOT NULL,
          parent_id uuid NOT NULL
      );
      ALTER TABLE ONLY public.ignored_destination_children ADD CONSTRAINT ignored_destination_children_pkey PRIMARY KEY (id);
      """)

    resources = %{
      "ignored_destination_parents" =>
        {nil, OfficeGraph.TestSupport.MigrationConformanceIgnoredDestinationParentResource},
      "ignored_destination_children" =>
        {nil, OfficeGraph.TestSupport.MigrationConformanceIgnoredDestinationChildResource}
    }

    assert inventory
           |> synthetic_terminal_errors(resources, [])
           |> without_framework_presence_errors() == []
  end

  test "terminal errors omit references with migration-ignored source attributes" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.ignored_reference_parents (
          id uuid NOT NULL
      );
      CREATE TABLE public.ignored_source_children (
          id uuid NOT NULL
      );
      ALTER TABLE ONLY public.ignored_reference_parents ADD CONSTRAINT ignored_reference_parents_pkey PRIMARY KEY (id);
      ALTER TABLE ONLY public.ignored_source_children ADD CONSTRAINT ignored_source_children_pkey PRIMARY KEY (id);
      """)

    resources = %{
      "ignored_reference_parents" =>
        {nil, OfficeGraph.TestSupport.MigrationConformanceIgnoredReferenceParentResource},
      "ignored_source_children" =>
        {nil, OfficeGraph.TestSupport.MigrationConformanceIgnoredSourceChildResource}
    }

    assert inventory
           |> synthetic_terminal_errors(resources, [])
           |> without_framework_presence_errors() == []
  end

  test "terminal errors honor configured PostgreSQL migration types" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.network_endpoints (
          address inet NOT NULL
      );
      """)

    assert inventory
           |> synthetic_terminal_errors(%{
             "network_endpoints" =>
               {nil, OfficeGraph.TestSupport.MigrationConformanceNetworkResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal errors keep PostgreSQL name types catalog-owned" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.catalog_names (
          catalog_name name NOT NULL
      );
      """)

    assert inventory
           |> synthetic_terminal_errors(%{
             "catalog_names" => {nil, OfficeGraph.TestSupport.MigrationConformanceNameResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal errors canonicalize built-in PostgreSQL migration types and aliases" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.small_scores (
          score smallint NOT NULL,
          alias_score smallint NOT NULL
      );
      """)

    assert inventory
           |> synthetic_terminal_errors(%{
             "small_scores" => {nil, OfficeGraph.TestSupport.MigrationConformanceSmallintResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal errors keep PostgreSQL object identifier types unqualified" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.catalog_references (
          object_id oid NOT NULL,
          relation_ref regclass NOT NULL,
          namespace_ref regnamespace NOT NULL,
          transaction_id xid8 NOT NULL,
          tuple_id tid NOT NULL
      );
      """)

    assert inventory
           |> synthetic_terminal_errors(%{
             "catalog_references" =>
               {nil, OfficeGraph.TestSupport.MigrationConformanceObjectIdentifierResource}
           })
           |> without_framework_presence_errors() == []
  end

  test "terminal errors qualify custom migration types in default casts" do
    inventory =
      MigrationConformanceSupport.parse_dump("""
      CREATE TABLE public.review_items (
          "status" public."review_status" DEFAULT 'pending'::public.review_status NOT NULL
      );
      """)

    assert inventory
           |> synthetic_terminal_errors(
             %{
               "review_items" =>
                 {nil, OfficeGraph.TestSupport.MigrationConformanceCustomTypeResource}
             },
             []
           )
           |> without_framework_presence_errors() == []
  end

  test "terminal errors quote custom migration types and default casts in configured schemas" do
    inventory =
      MigrationConformanceSupport.parse_dump(~S'''
      CREATE TABLE "Audit Space"."Typed Reviews" (
          status "Audit Space".review_status DEFAULT 'pending'::"Audit Space".review_status NOT NULL
      );
      ''')

    assert inventory
           |> synthetic_terminal_errors(
             %{
               "Typed Reviews" =>
                 {nil, OfficeGraph.TestSupport.MigrationConformanceQuotedCustomTypeResource}
             },
             []
           )
           |> without_framework_presence_errors() == []
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

  test "terminal constraints split quoted comma identifiers only outside quotes" do
    inventory =
      MigrationConformanceSupport.parse_dump(~S'''
      CREATE TABLE public.quoted_comma_parents (
          "tenant,id" uuid NOT NULL,
          parent_scope uuid NOT NULL
      );
      CREATE TABLE public.quoted_comma_children (
          id uuid NOT NULL,
          "parent,id" uuid NOT NULL,
          child_scope uuid NOT NULL
      );
      ALTER TABLE ONLY public.quoted_comma_parents ADD CONSTRAINT quoted_comma_parents_pkey PRIMARY KEY ("tenant,id");
      ALTER TABLE ONLY public.quoted_comma_children ADD CONSTRAINT quoted_comma_children_pkey PRIMARY KEY (id);
      ALTER TABLE ONLY public.quoted_comma_children ADD CONSTRAINT quoted_comma_children_parent_fkey FOREIGN KEY ("parent,id", child_scope) REFERENCES public.quoted_comma_parents("tenant,id", parent_scope);
      ''')

    errors =
      MigrationConformanceSupport.terminal_database_errors(
        %{
          "quoted_comma_children" =>
            {nil, OfficeGraph.TestSupport.MigrationConformanceQuotedCommaChildResource},
          "quoted_comma_parents" =>
            {nil, OfficeGraph.TestSupport.MigrationConformanceQuotedCommaParentResource}
        },
        inventory
      )

    refute Enum.any?(errors, &String.contains?(&1, "quoted_comma_children_parent_fkey"))
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

  defp without_framework_presence_errors(errors) do
    Enum.reject(errors, &MapSet.member?(@framework_presence_errors, &1))
  end

  defp synthetic_terminal_errors(inventory, resources, approvals \\ []) do
    MigrationConformanceSupport.terminal_database_errors(resources, inventory, approvals)
  end
end
