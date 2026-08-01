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
end
