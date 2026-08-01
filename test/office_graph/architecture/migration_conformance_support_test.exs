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

  test "includes DDL from every reachable clause of a local migration helper" do
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
          create_examples(:primary)
        end

        defp create_examples(:primary) do
          create table(:primary_clause_examples)
        end

        defp create_examples(_kind) do
          create table(:fallback_clause_examples)
        end
      end
      """
    )

    File.cd!(root, fn ->
      assert MigrationConformanceSupport.migration_tables() == [
               "fallback_clause_examples",
               "primary_clause_examples"
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
