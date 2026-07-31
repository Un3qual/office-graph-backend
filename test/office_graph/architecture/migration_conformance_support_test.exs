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
end
