defmodule OfficeGraph.Architecture.MigrationConformanceSupportTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.TestSupport.MigrationConformanceSupport

  test "derives table lifecycle only from executable forward migration syntax" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        @migration_note "create table(:string_only)"

        def up do
          # create table(:comment_only)
          message = "create table(:string_only)"

          create table(
                   :multiline_examples
                 ) do
            add :name, :text
          end
        end

        def down do
          drop table(:multiline_examples)
        end
      end
      """
    )

    File.write!(
      Path.join(migrations, "20260731000001_replace_examples.exs"),
      """
      defmodule ReplaceExamples do
        use Ecto.Migration

        def change do
          message = "drop table(:multiline_examples)"

          drop table(
                 :multiline_examples
               )

          create table(:surviving_examples)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == ["surviving_examples"]
    end)
  end

  test "includes conditional create and drop operations in the table lifecycle" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_conditional_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create_if_not_exists table(:conditionally_created_examples)
          create table(:conditionally_dropped_examples)
        end
      end
      """
    )

    File.write!(
      Path.join(migrations, "20260731000001_drop_examples.exs"),
      """
      defmodule DropExamples do
        use Ecto.Migration

        def change do
          drop_if_exists table(:conditionally_dropped_examples)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "conditionally_created_examples"
             ]
    end)
  end

  test "applies table renames to terminal table and foreign-key identities" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_rename_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create table(:old_parents)

          create table(:old_children) do
            add :parent_id, references(:old_parents)
          end
        end
      end
      """
    )

    File.write!(
      Path.join(migrations, "20260731000001_rename_examples.exs"),
      """
      defmodule RenameExamples do
        use Ecto.Migration

        def change do
          rename table(:old_parents), to: table(:new_parents)
          rename table(:old_children), to: table(:new_children)
        end
      end
      """
    )

    expected_resources = %{
      "new_children" => {nil, OfficeGraph.Tenancy.Organization},
      "new_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "new_children",
               "new_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "new_children.parent_id references new_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "executes only statically selected migration branches" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_static_branch_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          if true do
            create table(:selected_true_examples)
          else
            drop table(:selected_true_examples)
          end

          if false do
            create table(:unreachable_false_examples)
          else
            create table(:selected_false_examples)
          end
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "selected_false_examples",
               "selected_true_examples"
             ]
    end)
  end

  test "executes only statically selected foreign-key branches" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_static_foreign_key_branch_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create table(:parents)

          create table(:children) do
            if true do
              add :parent_id, references(:parents)
            else
              remove :parent_id
            end
          end
        end
      end
      """
    )

    expected_resources = %{
      "children" => {nil, OfficeGraph.Tenancy.Organization},
      "parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "keeps tables that may exist after an unknown migration branch" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_unknown_branch_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          if System.get_env("CREATE_OPTIONAL_EXAMPLES") do
            create table(:possible_examples)
          else
            drop table(:possible_examples)
          end
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == ["possible_examples"]
    end)
  end

  test "keeps foreign keys that may exist after an unknown migration branch" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_unknown_foreign_key_branch_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create table(:parents)

          create table(:children) do
            if System.get_env("CREATE_PARENT_REFERENCE") do
              add :parent_id, references(:parents)
            else
              remove :parent_id
            end
          end
        end
      end
      """
    )

    expected_resources = %{
      "children" => {nil, OfficeGraph.Tenancy.Organization},
      "parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "applies source and destination column renames to foreign-key identities" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_column_rename_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create table(:parents, primary_key: false) do
            add :legacy_id, :uuid, primary_key: true
          end

          create table(:children) do
            add :parent_id, references(:parents, column: :legacy_id)
          end
        end
      end
      """
    )

    File.write!(
      Path.join(migrations, "20260731000001_rename_examples.exs"),
      """
      defmodule RenameExamples do
        use Ecto.Migration

        def change do
          rename table(:children), :parent_id, to: :owner_id
          rename table(:parents), :legacy_id, to: :external_id
        end
      end
      """
    )

    expected_resources = %{
      "children" => {nil, OfficeGraph.Tenancy.Organization},
      "parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.owner_id references parents.external_id without a matching belongs_to"
             ]
    end)
  end

  test "removes foreign keys when their constraints are dropped" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_constraint_drop_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create table(:parents)

          create table(:children) do
            add :parent_id, references(:parents)

            add :alternate_parent_id,
                references(:parents, name: "children_alternate_parent_fkey")
          end
        end
      end
      """
    )

    File.write!(
      Path.join(migrations, "20260731000001_drop_constraints.exs"),
      """
      defmodule DropConstraints do
        use Ecto.Migration

        def change do
          drop constraint(:children, "children_parent_id_fkey")
          drop_if_exists constraint(:children, "children_alternate_parent_fkey")
        end
      end
      """
    )

    expected_resources = %{
      "children" => {nil, OfficeGraph.Tenancy.Organization},
      "parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == []
    end)
  end

  test "includes DDL from reachable local migration helpers" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_helper_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def up do
          create_examples(:helper_created_examples)
        end

        defp create_examples(table_name) do
          create_parent()

          create table(table_name) do
            add :parent_id, references(:helper_parent_examples)
          end
        end

        defp create_parent do
          create table(:helper_parent_examples)
        end

        defp unreachable_helper do
          create table(:unreachable_examples)
        end

        def down do
          drop table(:helper_created_examples)
          drop table(:helper_parent_examples)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "helper_created_examples",
               "helper_parent_examples"
             ]
    end)
  end

  test "resolves sequential local table bindings in forward migration DDL" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_local_binding_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          child_table = :locally_bound_children
          parent_table = :locally_bound_parents

          create table(parent_table)
          create_child(child_table, parent_table)

          if true do
            nested_table = :locally_bound_nested
            create table(nested_table)
          end
        end

        defp create_child(child_table, parent_table) do
          create table(child_table) do
            add :parent_id, references(parent_table)
          end
        end
      end
      """
    )

    expected_resources = %{
      "locally_bound_children" => {nil, OfficeGraph.Tenancy.Organization},
      "locally_bound_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "locally_bound_children",
               "locally_bound_nested",
               "locally_bound_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "locally_bound_children.parent_id references locally_bound_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "keeps local helper bindings isolated from the caller" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_helper_binding_scope_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          table_name = :caller_scope_examples
          create_helper_table()
          create table(table_name)
        end

        defp create_helper_table do
          table_name = :helper_scope_examples
          create table(table_name)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "caller_scope_examples",
               "helper_scope_examples"
             ]
    end)
  end

  test "includes DDL expanded from reachable local migration macros" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_macro_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        defmacrop create_pair(child_table, parent_table) do
          quote do
            create table(unquote(parent_table))

            create table(unquote(child_table)) do
              add :parent_id, references(unquote(parent_table))
            end
          end
        end

        def change do
          create_pair(:macro_children, :macro_parents)
        end
      end
      """
    )

    expected_resources = %{
      "macro_children" => {nil, OfficeGraph.Tenancy.Organization},
      "macro_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "macro_children",
               "macro_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "macro_children.parent_id references macro_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "includes DDL expanded from bind_quoted migration macros" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_bind_quoted_macro_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        defmacrop create_pair(child_table, parent_table) do
          quote bind_quoted: [child_table: child_table, parent_table: parent_table] do
            create table(parent_table)

            create table(child_table) do
              add :parent_id, references(parent_table)
            end
          end
        end

        def change do
          create_pair(:quoted_children, :quoted_parents)
        end
      end
      """
    )

    expected_resources = %{
      "quoted_children" => {nil, OfficeGraph.Tenancy.Organization},
      "quoted_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "quoted_children",
               "quoted_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "quoted_children.parent_id references quoted_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "ignores DDL owned by auxiliary modules in a migration file" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_module_scope_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule BeforeMigrationHelper do
        def change, do: create(table(:before_helper_examples))
      end

      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create table(:owned_examples)
        end

        defmodule NestedHelper do
          def change, do: create(table(:nested_helper_examples))
        end
      end

      defmodule AfterMigrationHelper do
        def change, do: create(table(:after_helper_examples))
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == ["owned_examples"]
    end)
  end

  test "includes DDL from migration helpers called through default arguments" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_default_helper_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create_examples()
          create_examples(:explicit_default_helper_examples)
        end

        defp create_examples(table_name \\\\ :default_helper_examples) do
          create table(table_name)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "default_helper_examples",
               "explicit_default_helper_examples"
             ]
    end)
  end

  test "includes DDL only from the matching local migration helper clause" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_clause_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def up do
          ddl(:add)
          reverse_ddl(:add)
        end

        defp ddl(:add) do
          create table(:matching_clause_examples)
        end

        defp ddl(:remove) do
          drop table(:matching_clause_examples)
        end

        defp reverse_ddl(:remove) do
          drop table(:reverse_matching_clause_examples)
        end

        defp reverse_ddl(:add) do
          create table(:reverse_matching_clause_examples)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "matching_clause_examples",
               "reverse_matching_clause_examples"
             ]
    end)
  end

  test "selects statically matching guarded migration helper clauses" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_guarded_clause_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def up do
          guarded_ddl(:add)
          reverse_guarded_ddl(:add)
        end

        defp guarded_ddl(mode) when mode == :add do
          create table(:guarded_clause_examples)
        end

        defp guarded_ddl(_mode) do
          drop table(:guarded_clause_examples)
        end

        defp reverse_guarded_ddl(mode) when mode == :remove do
          drop table(:reverse_guarded_clause_examples)
        end

        defp reverse_guarded_ddl(_mode) do
          create table(:reverse_guarded_clause_examples)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "guarded_clause_examples",
               "reverse_guarded_clause_examples"
             ]
    end)
  end

  test "selects statically matching migration helper clauses with chained guards" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_chained_guard_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def up do
          guarded_ddl(:add)
          reverse_guarded_ddl(:add)
        end

        defp guarded_ddl(mode) when mode != :remove when mode == :add do
          create table(:chained_guard_clause_examples)
        end

        defp guarded_ddl(_mode) do
          drop table(:chained_guard_clause_examples)
        end

        defp reverse_guarded_ddl(mode) when mode == :remove when mode != :add do
          drop table(:reverse_chained_guard_clause_examples)
        end

        defp reverse_guarded_ddl(_mode) do
          create table(:reverse_chained_guard_clause_examples)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "chained_guard_clause_examples",
               "reverse_chained_guard_clause_examples"
             ]
    end)
  end

  test "substitutes bindings from destructured migration helper parameters" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_destructured_helper_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def up do
          create_pair({:destructured_children, :destructured_parents})
        end

        defp create_pair({child, parent}) do
          create table(parent)

          create table(child) do
            add :parent_id, references(parent)
          end
        end
      end
      """
    )

    expected_resources = %{
      "destructured_children" => {nil, OfficeGraph.Tenancy.Organization},
      "destructured_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "destructured_children",
               "destructured_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "destructured_children.parent_id references destructured_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "requires repeated migration helper variables to unify" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_unified_helper_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create_examples({:first_table, :second_table})
        end

        defp create_examples({table, table}) do
          create table(table)
        end

        defp create_examples({_left, _right}) do
          create table(:fallback_table)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == ["fallback_table"]
    end)
  end

  test "parameter substitution does not re-enter replacement expressions" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_substitution_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def up do
          name = :ignored
          create_examples(prefixed(name))
        end

        defp create_examples(name) do
          create table(name)
        end

        defp prefixed(_name), do: :replacement_expression_examples
      end
      """
    )

    File.cd!(root, fn ->
      task = Task.async(&MigrationConformanceSupport.migration_tables/0)

      case Task.yield(task, 2_000) do
        {:ok, tables} ->
          assert tables == ["replacement_expression_examples"]

        nil ->
          Task.shutdown(task, :brutal_kill)
          flunk("migration table extraction did not terminate")
      end
    end)
  end

  test "reports foreign keys declared by conditional table creates" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_conditional_foreign_key_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create_if_not_exists table(:conditional_children) do
            add :parent_id, references(:conditional_parents)
          end
        end
      end
      """
    )

    expected_resources = %{
      "conditional_children" => {nil, OfficeGraph.Tenancy.Organization},
      "conditional_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "conditional_children.parent_id references conditional_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "removes foreign keys when a table is conditionally dropped and recreated" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_conditional_foreign_key_drop_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create table(:conditional_children) do
            add :parent_id, references(:conditional_parents)
          end
        end
      end
      """
    )

    File.write!(
      Path.join(migrations, "20260731000001_drop_examples.exs"),
      """
      defmodule DropExamples do
        use Ecto.Migration

        def change do
          drop_if_exists table(:conditional_children), mode: :cascade
        end
      end
      """
    )

    File.write!(
      Path.join(migrations, "20260731000002_recreate_examples.exs"),
      """
      defmodule RecreateExamples do
        use Ecto.Migration

        def change do
          create table(:conditional_children) do
            add :label, :text
          end
        end
      end
      """
    )

    expected_resources = %{
      "conditional_children" => {nil, OfficeGraph.Tenancy.Organization},
      "conditional_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == []
    end)
  end

  test "resolves migration module attributes at each definition site" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_module_attribute_migration_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        use Ecto.Migration

        @table :attribute_parents
        defp create_parent do
          create table(@table)
        end

        @table :attribute_children
        @parent_table :attribute_parents

        def change do
          create_parent()

          create table(@table) do
            add :parent_id, references(@parent_table)
          end
        end
      end
      """
    )

    expected_resources = %{
      "attribute_children" => {nil, OfficeGraph.Tenancy.Organization},
      "attribute_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "attribute_children",
               "attribute_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "attribute_children.parent_id references attribute_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "resolves aliases when selecting the owning migration module" do
    root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_aliased_migration_module_conformance_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.write!(
      Path.join(migrations, "20260731000000_create_examples.exs"),
      """
      defmodule CreateExamples do
        alias Ecto.Migration, as: Migration
        use Migration

        def change do
          create table(:aliased_parents)

          create table(:aliased_children) do
            add :parent_id, references(:aliased_parents)
          end
        end
      end
      """
    )

    expected_resources = %{
      "aliased_children" => {nil, OfficeGraph.Tenancy.Organization},
      "aliased_parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "aliased_children",
               "aliased_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "aliased_children.parent_id references aliased_parents.id without a matching belongs_to"
             ]
    end)
  end
end
