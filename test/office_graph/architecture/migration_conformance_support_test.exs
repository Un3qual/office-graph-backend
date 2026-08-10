defmodule OfficeGraph.Architecture.MigrationConformanceSupportTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.TestSupport.MigrationConformanceSupport

  test "derives table lifecycle only from executable forward migration syntax" do
    in_migration_root("office_graph_migration_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == ["surviving_examples"]
    end)
  end

  test "ignores inert quoted and anonymous-function migration bodies" do
    in_migration_root("office_graph_inert_ast_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:durable_parents)

            create table(:durable_children) do
              add :parent_id, references(:durable_parents)
            end

            quote do
              unquote(create table(:created_while_quoting))
              drop table(:durable_parents)

              alter table(:durable_children) do
                remove :parent_id
              end
            end

            fn ->
              drop table(:durable_parents)

              alter table(:durable_children) do
                remove :parent_id
              end
            end
          end
        end
        """
      )

      expected_resources = %{
        "durable_children" => {nil, OfficeGraph.Tenancy.Organization},
        "durable_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_tables() == [
               "created_while_quoting",
               "durable_children",
               "durable_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "durable_children.parent_id references durable_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "includes conditional create and drop operations in the table lifecycle" do
    in_migration_root("office_graph_conditional_migration_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == [
               "conditionally_created_examples"
             ]
    end)
  end

  test "applies table renames to terminal table and foreign-key identities" do
    in_migration_root("office_graph_rename_migration_conformance", fn root, migrations ->
      _ = root

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

  test "reuses one migration analysis per working directory" do
    first_root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_cached_migration_conformance_#{System.unique_integer([:positive])}"
      )

    second_root =
      Path.join(
        System.tmp_dir!(),
        "office_graph_isolated_migration_conformance_#{System.unique_integer([:positive])}"
      )

    first_migrations = Path.join(first_root, "priv/repo/migrations")
    second_migrations = Path.join(second_root, "priv/repo/migrations")
    File.mkdir_p!(first_migrations)
    File.mkdir_p!(second_migrations)
    on_exit(fn -> File.rm_rf!(first_root) end)
    on_exit(fn -> File.rm_rf!(second_root) end)

    first_migration = Path.join(first_migrations, "20260731000000_create_examples.exs")

    File.write!(
      first_migration,
      """
      defmodule CreateExamples do
        use Ecto.Migration

        def change do
          create table(:parents)

          create table(:children) do
            add :parent_id, references(:parents)
          end
        end
      end
      """
    )

    File.write!(
      Path.join(second_migrations, "20260731000000_create_other.exs"),
      """
      defmodule CreateOther do
        use Ecto.Migration

        def change, do: create(table(:other_examples))
      end
      """
    )

    expected_resources = %{
      "children" => {nil, OfficeGraph.Tenancy.Organization},
      "parents" => {nil, OfficeGraph.Tenancy.Workspace}
    }

    File.cd!(first_root, fn ->
      assert MigrationConformanceSupport.migration_tables() == ["children", "parents"]

      File.write!(first_migration, "this is no longer valid Elixir")

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)

    File.cd!(second_root, fn ->
      assert MigrationConformanceSupport.migration_tables() == ["other_examples"]
    end)
  end

  test "executes only statically selected migration branches" do
    in_migration_root("office_graph_static_branch_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == [
               "selected_false_examples",
               "selected_true_examples"
             ]
    end)
  end

  test "executes only the statically matching case branch" do
    in_migration_root("office_graph_static_case_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            case :create do
              :create -> create table(:case_selected_examples)
              :drop -> drop table(:case_selected_examples)
            end
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == ["case_selected_examples"]
    end)
  end

  test "keeps tables dropped only by an alternative receive clause" do
    in_migration_root("office_graph_receive_table_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:durable)

            send(self(), :keep)

            receive do
              :keep -> :ok
              :drop -> drop table(:durable)
            end
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == ["durable"]
    end)
  end

  test "executes only statically selected foreign-key branches" do
    in_migration_root("office_graph_static_foreign_key_branch", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "keeps foreign keys removed only by an alternative receive clause" do
    in_migration_root("office_graph_receive_foreign_key_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents)

            create table(:children) do
              add :parent_id, references(:parents)
            end

            send(self(), :keep)

            alter table(:children) do
              receive do
                :keep -> :ok
                :drop -> remove :parent_id
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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "keeps tables that may exist after an unknown migration branch" do
    in_migration_root("office_graph_unknown_branch_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == ["possible_examples"]
    end)
  end

  test "keeps tables that may survive an unresolved cond branch" do
    in_migration_root("office_graph_unknown_cond_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260806000000_create_durable.exs"),
        """
        defmodule CreateDurable do
          use Ecto.Migration

          def change do
            create table(:durable)

            cond do
              System.get_env("DROP_DURABLE") -> drop table(:durable)
              true -> :ok
            end
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == ["durable"]
    end)
  end

  test "keeps tables dropped only by unresolved short-circuit operands" do
    in_migration_root("office_graph_unknown_short_circuit_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_durable.exs"),
        """
        defmodule CreateDurable do
          use Ecto.Migration

          def change do
            create table(:durable_symbolic_and)
            create table(:durable_strict_and)
            create table(:durable_symbolic_or)
            create table(:durable_strict_or)

            System.get_env("DROP_SYMBOLIC_AND") && drop(table(:durable_symbolic_and))
            (System.get_env("DROP_STRICT_AND") != nil) and drop(table(:durable_strict_and))
            System.get_env("KEEP_SYMBOLIC_OR") || drop(table(:durable_symbolic_or))
            is_nil(System.get_env("KEEP_STRICT_OR")) or drop(table(:durable_strict_or))
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == [
               "durable_strict_and",
               "durable_strict_or",
               "durable_symbolic_and",
               "durable_symbolic_or"
             ]
    end)
  end

  test "resolves statically known short-circuit migration operands" do
    in_migration_root("office_graph_static_short_circuit_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_durable.exs"),
        """
        defmodule CreateDurable do
          use Ecto.Migration

          def change do
            create table(:kept_by_symbolic_and)
            create table(:dropped_by_strict_and)
            create table(:dropped_by_symbolic_or)
            create table(:kept_by_strict_or)

            false && drop(table(:kept_by_symbolic_and))
            true and drop(table(:dropped_by_strict_and))
            false || drop(table(:dropped_by_symbolic_or))
            true or drop(table(:kept_by_strict_or))
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == [
               "kept_by_strict_or",
               "kept_by_symbolic_and"
             ]
    end)
  end

  test "models static and unresolved with generator branches" do
    in_migration_root("office_graph_with_branch_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_durable.exs"),
        """
        defmodule CreateDurable do
          use Ecto.Migration

          def change do
            create table(:possibly_dropped_by_do)
            create table(:possibly_dropped_by_else)
            create table(:kept_by_static_mismatch)
            create table(:dropped_by_static_match)
            create table(:dropped_by_static_else)

            with {:ok, _value} <- System.fetch_env("DROP_DURABLE") do
              drop table(:possibly_dropped_by_do)
            else
              :error -> drop table(:possibly_dropped_by_else)
            end

            with :ok <- :error, do: drop(table(:kept_by_static_mismatch))
            with :ok <- :ok, do: drop(table(:dropped_by_static_match))

            with :ok <- :error do
              :ok
            else
              :error -> drop table(:dropped_by_static_else)
            end
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == [
               "kept_by_static_mismatch",
               "possibly_dropped_by_do",
               "possibly_dropped_by_else"
             ]
    end)
  end

  test "ignores table drops in statically unmatched try else clauses" do
    in_migration_root("office_graph_static_try_else_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_durable.exs"),
        """
        defmodule CreateDurable do
          use Ecto.Migration

          def change do
            create table(:durable)

            try do
              :ok
            else
              :ok -> :ok
              :error -> drop table(:durable)
            end
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == ["durable"]
    end)
  end

  test "keeps foreign keys that may exist after an unknown migration branch" do
    in_migration_root("office_graph_unknown_foreign_key_branch", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "keeps foreign keys removed only by an unresolved short-circuit operand" do
    in_migration_root("office_graph_unknown_foreign_key_short_circuit", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents)

            create table(:children) do
              add :parent_id, references(:parents)
              System.get_env("REMOVE_PARENT_REFERENCE") && remove(:parent_id)
            end
          end
        end
        """
      )

      expected_resources = %{
        "children" => {nil, OfficeGraph.Tenancy.Organization},
        "parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "keeps foreign keys removed only by an unresolved with generator" do
    in_migration_root("office_graph_unknown_foreign_key_with", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents)

            create table(:children) do
              add :parent_id, references(:parents)
            end

            with {:ok, _value} <- System.fetch_env("REMOVE_PARENT_REFERENCE") do
              alter table(:children) do
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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "keeps foreign keys that may survive an unresolved cond branch" do
    in_migration_root("office_graph_unknown_foreign_key_cond", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260806000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents)

            create table(:children) do
              add :parent_id, references(:parents)
            end

            alter table(:children) do
              cond do
                System.get_env("DROP_PARENT_REFERENCE") -> remove :parent_id
                true -> :ok
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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "ignores foreign-key removals in statically unmatched try else clauses" do
    in_migration_root("office_graph_static_foreign_key_try_else", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents)

            create table(:children) do
              add :parent_id, references(:parents)
            end

            alter table(:children) do
              try do
                :ok
              else
                :ok -> :ok
                :error -> remove :parent_id
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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "keeps schema state that an unknown comprehension filter may remove" do
    in_migration_root("office_graph_unknown_comprehension_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents)

            create table(:children) do
              add :parent_id, references(:parents)
            end

            create table(:possibly_removed)

            for _iteration <- [:once], System.get_env("REMOVE_OPTIONAL_SCHEMA") do
              drop table(:possibly_removed)

              alter table(:children) do
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

      assert MigrationConformanceSupport.migration_tables() == [
               "children",
               "parents",
               "possibly_removed"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.parent_id references parents.id without a matching belongs_to"
             ]
    end)
  end

  test "applies source and destination column renames to foreign-key identities" do
    in_migration_root("office_graph_column_rename_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "children.owner_id references parents.external_id without a matching belongs_to"
             ]
    end)
  end

  test "removes foreign keys when their constraints are dropped" do
    in_migration_root("office_graph_constraint_drop_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == []
    end)
  end

  test "removes foreign keys when their columns are conditionally removed" do
    in_migration_root("office_graph_conditional_column_remove_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents)

            create table(:children) do
              add :parent_id, references(:parents)
            end
          end
        end
        """
      )

      File.write!(
        Path.join(migrations, "20260731000001_remove_parent.exs"),
        """
        defmodule RemoveParent do
          use Ecto.Migration

          def change do
            alter table(:children) do
              remove_if_exists :parent_id, references(:parents)
            end
          end
        end
        """
      )

      expected_resources = %{
        "children" => {nil, OfficeGraph.Tenancy.Organization},
        "parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == []
    end)
  end

  test "includes DDL from reachable local migration helpers" do
    in_migration_root("office_graph_helper_migration_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == [
               "helper_created_examples",
               "helper_parent_examples"
             ]
    end)
  end

  test "includes DDL from exported local migration helpers invoked through static apply" do
    in_migration_root("office_graph_apply_helper_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260805000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def up do
            apply(__MODULE__, :create_first, [])
            Kernel.apply(__MODULE__, :create_second, [])
            :erlang.apply(__MODULE__, :create_third, [])

            receiver = __MODULE__
            local_operation = :create_fourth
            kernel_operation = :create_fifth
            erlang_operation = :create_sixth
            apply(receiver, local_operation, [])
            Kernel.apply(receiver, kernel_operation, [])
            :erlang.apply(receiver, erlang_operation, [])
          end

          def create_first, do: create(table(:apply_helper_first))
          def create_second, do: create(table(:apply_helper_second))
          def create_third, do: create(table(:apply_helper_third))
          def create_fourth, do: create(table(:apply_helper_fourth))
          def create_fifth, do: create(table(:apply_helper_fifth))
          def create_sixth, do: create(table(:apply_helper_sixth))
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == [
               "apply_helper_fifth",
               "apply_helper_first",
               "apply_helper_fourth",
               "apply_helper_second",
               "apply_helper_sixth",
               "apply_helper_third"
             ]
    end)
  end

  test "resolves sequential local table bindings in forward migration DDL" do
    in_migration_root("office_graph_local_binding_conformance", fn root, migrations ->
      _ = root

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
    in_migration_root("office_graph_helper_binding_scope", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == [
               "caller_scope_examples",
               "helper_scope_examples"
             ]
    end)
  end

  test "includes DDL expanded from reachable local migration macros" do
    in_migration_root("office_graph_macro_migration_conformance", fn root, migrations ->
      _ = root

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
    in_migration_root("office_graph_bind_quoted_macro_conformance", fn root, migrations ->
      _ = root

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
    in_migration_root("office_graph_module_scope_migration_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == ["owned_examples"]
    end)
  end

  test "includes DDL from migration helpers called through default arguments" do
    in_migration_root("office_graph_default_helper_migration_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == [
               "default_helper_examples",
               "explicit_default_helper_examples"
             ]
    end)
  end

  test "includes DDL only from the matching local migration helper clause" do
    in_migration_root("office_graph_clause_migration_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == [
               "matching_clause_examples",
               "reverse_matching_clause_examples"
             ]
    end)
  end

  test "selects statically matching guarded migration helper clauses" do
    in_migration_root("office_graph_guarded_clause_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == [
               "guarded_clause_examples",
               "reverse_guarded_clause_examples"
             ]
    end)
  end

  test "selects statically matching migration helper clauses with chained guards" do
    in_migration_root("office_graph_chained_guard_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == [
               "chained_guard_clause_examples",
               "reverse_chained_guard_clause_examples"
             ]
    end)
  end

  test "selects statically matching migration helper clauses with boolean guards" do
    in_migration_root("office_graph_boolean_guard_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def up do
            guarded_ddl(:add)
            alternative_guarded_ddl(:add)
          end

          defp guarded_ddl(mode) when mode == :add and mode != :remove do
            create table(:boolean_and_guard_examples)
          end

          defp guarded_ddl(_mode) do
            drop table(:boolean_and_guard_examples)
          end

          defp alternative_guarded_ddl(mode) when mode == :remove or mode == :add do
            create table(:boolean_or_guard_examples)
          end

          defp alternative_guarded_ddl(_mode) do
            drop table(:boolean_or_guard_examples)
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == [
               "boolean_and_guard_examples",
               "boolean_or_guard_examples"
             ]
    end)
  end

  test "expands statically enumerable migration comprehensions" do
    in_migration_root("office_graph_static_comprehension_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def up do
            for table_name <- [:static_users, :static_groups] do
              create table(table_name)
            end
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == ["static_groups", "static_users"]
    end)
  end

  test "expands invoked migration closures with their static arguments" do
    in_migration_root("office_graph_closure_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create_table = fn name -> create table(name) end

            create_child = fn child, parent ->
              create table(child) do
                add :parent_id, references(parent)
              end
            end

            create_table.(:closure_parents)
            create_child.(:closure_children, :closure_parents)
          end
        end
        """
      )

      expected_resources = %{
        "closure_children" => {nil, OfficeGraph.Tenancy.Organization},
        "closure_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_tables() == [
               "closure_children",
               "closure_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "closure_children.parent_id references closure_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "rejects migration execute SQL that changes table or foreign-key ownership" do
    Enum.each(
      [
        "CREATE TABLE sql_owned_examples (id uuid PRIMARY KEY)",
        "ALTER TABLE examples ADD CONSTRAINT examples_parent_fkey FOREIGN KEY (parent_id) REFERENCES parents(id)",
        "DROP TABLE IF EXISTS sql_owned_examples"
      ],
      fn sql ->
        in_migration_root("office_graph_sql_ddl_conformance", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260731000000_sql_ddl.exs"),
            """
            defmodule SqlDdl do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "rejects ownership DDL sent through migration repository query APIs" do
    Enum.each(
      [
        ~s'repo().query!("CREATE TABLE repo_owned_examples (id uuid PRIMARY KEY)", [])',
        ~s'repo().query_many!("CREATE TABLE repo_many_owned_examples (id uuid PRIMARY KEY)", [])',
        ~s'Ecto.Adapters.SQL.query(repo(), "CREATE TABLE adapter_owned_examples (id uuid PRIMARY KEY)", [])',
        ~s'Ecto.Adapters.SQL.query_many(repo(), "CREATE TABLE adapter_many_owned_examples (id uuid PRIMARY KEY)", [])',
        ~s'RepoAlias.query!("CREATE TABLE alias_owned_examples (id uuid PRIMARY KEY)", [])',
        ~s'RepoAlias.query_many!("CREATE TABLE alias_many_owned_examples (id uuid PRIMARY KEY)", [])'
      ],
      fn query_call ->
        in_migration_root("office_graph_query_ddl_conformance", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260805000000_query_ddl.exs"),
            """
            defmodule QueryDdl do
              use Ecto.Migration
              alias OfficeGraph.Repo, as: RepoAlias

              def change do
                #{query_call}
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "fails closed for lifecycle calls delegated to repository migration helpers" do
    Enum.each(
      [
        {"import MyApp.MigrationHelpers", "create_auxiliary_table()"},
        {"alias MyApp.MigrationHelpers, as: Helpers", "Helpers.create_auxiliary_table()"},
        {"", "MyApp.MigrationHelpers.create_auxiliary_table()"}
      ],
      fn {module_setup, helper_call} ->
        in_migration_root("office_graph_external_helper_conformance", fn root, migrations ->
          _ = root

          helpers = Path.join(root, "lib/my_app")
          File.mkdir_p!(helpers)

          File.write!(
            Path.join(helpers, "migration_helpers.ex"),
            """
            defmodule MyApp.MigrationHelpers do
              import Ecto.Migration

              def create_auxiliary_table do
                create table(:external_helper_owned)
              end
            end
            """
          )

          File.write!(
            Path.join(migrations, "20260805000000_external_helper.exs"),
            """
            defmodule ExternalHelperMigration do
              use Ecto.Migration
              #{module_setup}

              def change do
                #{helper_call}
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/repository migration helper/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "fails closed for lifecycle calls delegated to same-file migration helpers" do
    Enum.each(
      [
        {"import SameFileMigrationHelpers", "create_auxiliary_table()"},
        {"alias SameFileMigrationHelpers, as: Helpers", "Helpers.create_auxiliary_table()"},
        {"", "SameFileMigrationHelpers.create_auxiliary_table()"}
      ],
      fn {module_setup, helper_call} ->
        in_migration_root("office_graph_same_file_helper_conformance", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260810000000_same_file_helper.exs"),
            """
            defmodule SameFileMigrationHelpers do
              import Ecto.Migration

              def create_auxiliary_table do
                create table(:same_file_helper_owned)
              end
            end

            defmodule SameFileHelperMigration do
              use Ecto.Migration
              #{module_setup}

              def change do
                #{helper_call}
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/repository migration helper/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "fails closed for lifecycle calls exposed through repository defdelegates" do
    in_migration_root("office_graph_defdelegated_helper_conformance", fn root, migrations ->
      helpers = Path.join(root, "lib/my_app")
      File.mkdir_p!(helpers)

      File.write!(
        Path.join(helpers, "migration_helpers.ex"),
        """
        defmodule MyApp.MigrationHelpers do
          defdelegate create_auxiliary_table(), to: MyApp.RealMigrationHelpers
        end
        """
      )

      File.write!(
        Path.join(migrations, "20260805000000_defdelegated_helper.exs"),
        """
        defmodule DefdelegatedHelperMigration do
          use Ecto.Migration

          def change do
            MyApp.MigrationHelpers.create_auxiliary_table()
          end
        end
        """
      )

      assert_raise ArgumentError, ~r/repository migration helper/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "rejects ownership DDL inside executable migration DO blocks" do
    Enum.each(
      [
        "DO $$ BEGIN CREATE TABLE sql_owned_examples (id uuid); END $$;",
        "DO $body$ BEGIN ALTER TABLE examples ADD COLUMN label text; END $body$ LANGUAGE plpgsql;",
        "DO LANGUAGE plpgsql 'BEGIN DROP TABLE sql_owned_examples; END';",
        "DO $$ BEGIN EXECUTE 'CREATE TABLE sql_owned_examples (id uuid)'; END $$;",
        "DO $body$ BEGIN EXECUTE 'ALTER TABLE examples ADD COLUMN label text'; END $body$;",
        "DO LANGUAGE plpgsql 'BEGIN EXECUTE ''DROP TABLE sql_owned_examples''; END';",
        "DO $$ BEGIN EXECUTE format('CREATE TABLE %I (id uuid)', 'sql_owned_examples'); END $$;",
        "DO $$ BEGIN EXECUTE 'CREATE TABLE ' || quote_ident('sql_owned_examples') || ' (id uuid)'; END $$;"
      ],
      fn sql ->
        in_migration_root("office_graph_do_block_ddl", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260804000000_do_block_ddl.exs"),
            """
            defmodule DoBlockDdl do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "rejects ownership DDL inside migration procedure definitions" do
    Enum.each(
      [
        "CREATE PROCEDURE make_aux() LANGUAGE plpgsql AS $$ BEGIN CREATE TABLE auxiliary(id int); END $$; CALL make_aux();",
        "CREATE OR REPLACE FUNCTION make_aux() RETURNS void LANGUAGE plpgsql AS $body$ BEGIN ALTER TABLE examples ADD COLUMN label text; END $body$; SELECT make_aux();",
        "CREATE PROCEDURE drop_aux() LANGUAGE plpgsql AS 'BEGIN DROP TABLE auxiliary; END'; CALL drop_aux();"
      ],
      fn sql ->
        in_migration_root("office_graph_procedure_ddl", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260809000000_procedure_ddl.exs"),
            """
            defmodule ProcedureDdl do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "allows inert text inside migration procedure definitions" do
    in_migration_root("office_graph_inert_procedure_text", fn root, migrations ->
      _ = root

      sql = """
      CREATE PROCEDURE log_message() LANGUAGE plpgsql AS $$
      BEGIN
        RAISE NOTICE 'CREATE TABLE inert (id int)';
      END
      $$;
      CALL log_message();
      """

      File.write!(
        Path.join(migrations, "20260809000000_inert_procedure_text.exs"),
        """
        defmodule InertProcedureText do
          use Ecto.Migration

          def change do
            execute(#{inspect(sql)})
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == []
    end)
  end

  test "rejects ownership DDL in prefixed strings passed to dynamic EXECUTE" do
    Enum.each(
      [
        "DO $$ BEGIN EXECUTE E'CREATE TABLE escape_owned_examples (id uuid)'; END $$;",
        "DO $$ BEGIN EXECUTE E'SELECT \\'safe\\'; CREATE TABLE escaped_quote_owned_examples (id uuid)'; END $$;",
        "DO $$ BEGIN EXECUTE U&'CREATE TABLE unicode_owned_examples (id uuid)'; END $$;"
      ],
      fn sql ->
        in_migration_root("office_graph_prefixed_execute_ddl", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260806000000_prefixed_execute_ddl.exs"),
            """
            defmodule PrefixedExecuteDdl do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "rejects table-creating SELECT INTO migration SQL" do
    Enum.each(
      [
        "SELECT * INTO auxiliary FROM source_rows;",
        "WITH rows AS (SELECT * FROM source_rows) SELECT * INTO UNLOGGED TABLE auxiliary FROM rows;",
        "DO $$ BEGIN EXECUTE 'SELECT * INTO auxiliary FROM source_rows'; END $$;"
      ],
      fn sql ->
        in_migration_root("office_graph_select_into_ddl", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260809000000_select_into_ddl.exs"),
            """
            defmodule SelectIntoDdl do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "allows PL/pgSQL SELECT INTO variable assignment" do
    Enum.each(
      [
        "DO $$ DECLARE result integer; BEGIN SELECT 1 INTO result; END $$;",
        "DO $do$ DECLARE result integer; BEGIN SELECT 1 INTO result; END $do$;",
        "CREATE OR REPLACE FUNCTION count_items() RETURNS integer LANGUAGE plpgsql AS $$ DECLARE total integer; BEGIN SELECT count(*) INTO total FROM items; RETURN total; END $$;"
      ],
      fn sql ->
        in_migration_root("office_graph_non_table_select_into", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260809000000_non_table_select_into.exs"),
            """
            defmodule NonTableSelectInto do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert MigrationConformanceSupport.migration_tables() == []
        end)
      end
    )
  end

  test "ignores SELECT INTO text in inert dollar-quoted literals" do
    in_migration_root("office_graph_inert_select_into", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_inert_select_into.exs"),
        """
        defmodule InertSelectInto do
          use Ecto.Migration

          def change do
            execute("SELECT $do$ SELECT * INTO inert_table FROM source_rows $do$;")
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == []
    end)
  end

  test "rejects ownership DDL loaded by migration execute_file" do
    in_migration_root("office_graph_execute_file_ddl", fn root, migrations ->
      _ = root

      sql_directory = Path.join(root, "priv/repo/sql")
      File.mkdir_p!(sql_directory)

      File.write!(
        Path.join(migrations, "20260804000000_execute_file_ddl.exs"),
        """
        defmodule ExecuteFileDdl do
          use Ecto.Migration

          def change do
            execute_file("priv/repo/sql/change.pgsql")
          end
        end
        """
      )

      File.write!(
        Path.join(sql_directory, "change.pgsql"),
        "DO $$ BEGIN CREATE TABLE sql_owned_examples (id uuid); END $$;"
      )

      assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "rejects migration execute_file targets outside the project or without a regular file" do
    Enum.each(
      [
        {:escaping, "../shared/ddl.sql"},
        {:missing, "priv/repo/sql/missing.sql"},
        {:directory, "priv/repo/sql"}
      ],
      fn {scenario, execute_path} ->
        in_migration_root("office_graph_invalid_execute_file_#{scenario}", fn root, migrations ->
          _ = root

          if scenario == :escaping do
            File.mkdir_p!(Path.join(root, "shared"))
            File.write!(Path.join(root, "shared/ddl.sql"), "SELECT 1")
          end

          if scenario == :directory do
            File.mkdir_p!(Path.join(root, execute_path))
          end

          File.write!(
            Path.join(migrations, "20260804000000_execute_file.exs"),
            """
            defmodule InvalidExecuteFile do
              use Ecto.Migration

              def change do
                execute_file(#{inspect(execute_path)})
              end
            end
            """
          )

          assert_raise ArgumentError,
                       ~r/cannot statically resolve migration execute_file path inside project root/,
                       fn ->
                         MigrationConformanceSupport.migration_tables()
                       end
        end)
      end
    )
  end

  test "ignores ownership phrases in inert SQL literals inside and outside DO blocks" do
    Enum.each(
      [
        "SELECT $$ CREATE TABLE inert_examples $$",
        "DO $$ BEGIN RAISE NOTICE 'CREATE TABLE inert_examples'; END $$;",
        "DO $$ BEGIN EXECUTE 'SELECT ''CREATE TABLE inert_examples'''; END $$;",
        "DO $$ BEGIN EXECUTE format('SELECT %L', 'CREATE TABLE inert_examples'); END $$;",
        "DO $$ BEGIN EXECUTE 'SELECT ' || quote_literal('CREATE TABLE inert_examples'); END $$;",
        "DO $$ DECLARE value text := 'safe'; BEGIN EXECUTE 'SELECT ' || quote_literal(value || 'CREATE TABLE inert_examples'); END $$;"
      ],
      fn sql ->
        in_migration_root("office_graph_inert_sql_literal", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260804000000_inert_sql_literal.exs"),
            """
            defmodule InertSqlLiteral do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert MigrationConformanceSupport.migration_tables() == []
        end)
      end
    )
  end

  test "rejects migration execute SQL that changes foreign-table ownership" do
    Enum.each(
      [
        "CREATE FOREIGN TABLE auxiliary (id uuid) SERVER auxiliary_server",
        "ALTER FOREIGN TABLE auxiliary ADD COLUMN label text",
        "DROP FOREIGN TABLE IF EXISTS auxiliary"
      ],
      fn sql ->
        in_migration_root("office_graph_foreign_table_ddl", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260804000000_foreign_table_ddl.exs"),
            """
            defmodule ForeignTableDdl do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "rejects migration SQL that imports a foreign schema" do
    in_migration_root("office_graph_import_foreign_schema", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260810000000_import_foreign_schema.exs"),
        """
        defmodule ImportForeignSchema do
          use Ecto.Migration

          def change do
            execute("IMPORT FOREIGN SCHEMA remote FROM SERVER upstream INTO public")
          end
        end
        """
      )

      assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "treats SQL comments as whitespace when rejecting ownership DDL" do
    Enum.each(
      [
        "CREATE/* partitioned */TABLE sql_owned_examples (id uuid PRIMARY KEY)",
        "ALTER/* reason */TABLE examples ADD COLUMN label text",
        "DROP-- reason\nTABLE sql_owned_examples"
      ],
      fn sql ->
        in_migration_root("office_graph_commented_sql_ddl", fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260731000000_sql_ddl.exs"),
            """
            defmodule SqlDdl do
              use Ecto.Migration

              def change do
                execute(#{inspect(sql)})
              end
            end
            """
          )

          assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
            MigrationConformanceSupport.migration_tables()
          end
        end)
      end
    )
  end

  test "rejects statically interpolated migration execute SQL that changes ownership" do
    in_migration_root("office_graph_interpolated_sql_ddl_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_sql_ddl.exs"),
        ~S'''
        defmodule SqlDdl do
          use Ecto.Migration

          def change do
            execute("CREATE TABLE #{:interpolated_examples} (id uuid PRIMARY KEY)")
          end
        end
        '''
      )

      assert_raise ArgumentError, ~r/declarative Ecto migration constructs/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "substitutes bindings from destructured migration helper parameters" do
    in_migration_root("office_graph_destructured_helper_conformance", fn root, migrations ->
      _ = root

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
    in_migration_root("office_graph_unified_helper_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_tables() == ["fallback_table"]
    end)
  end

  test "selects only public migration entrypoints" do
    in_migration_root("office_graph_public_entrypoint_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:public_change_examples)
          end

          defp up do
            create table(:private_helper_examples)
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == ["public_change_examples"]
    end)
  end

  test "selects the first statically matching guarded migration entrypoint" do
    in_migration_root("office_graph_guarded_entrypoint_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260810000000_create_durable.exs"),
        """
        defmodule CreateDurable do
          use Ecto.Migration

          def change do
            create table(:durable)
          end
        end
        """
      )

      File.write!(
        Path.join(migrations, "20260810000001_guarded_drop.exs"),
        """
        defmodule GuardedDrop do
          use Ecto.Migration

          def up when false do
            drop table(:durable)
          end

          def up do
            :ok
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == ["durable"]
    end)
  end

  test "fails closed when a migration entrypoint guard cannot be resolved" do
    in_migration_root("office_graph_unresolved_entrypoint_guard", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260810000000_guarded_drop.exs"),
        """
        defmodule GuardedDrop do
          use Ecto.Migration

          def up when node() == :migration_runner do
            drop table(:durable)
          end

          def up do
            :ok
          end
        end
        """
      )

      assert_raise ArgumentError, ~r/cannot statically verify guarded migration entrypoint/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "fails closed when no guarded migration entrypoint clause matches" do
    in_migration_root("office_graph_unmatched_entrypoint_guard", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260810000000_guarded_drop.exs"),
        """
        defmodule GuardedDrop do
          use Ecto.Migration

          def up when false do
            drop table(:durable)
          end

          def change do
            create table(:incorrect_fallback)
          end
        end
        """
      )

      assert_raise ArgumentError, ~r/no statically matching guarded migration entrypoint/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "parameter substitution does not re-enter replacement expressions" do
    in_migration_root("office_graph_substitution_migration_conformance", fn root, migrations ->
      _ = root

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
    in_migration_root("office_graph_conditional_foreign_key_conformance", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "conditional_children.parent_id references conditional_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "reports foreign keys added conditionally to existing tables" do
    in_migration_root("office_graph_conditional_add_foreign_key", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:conditional_parents)
            create table(:conditional_children)

            alter table(:conditional_children) do
              add_if_not_exists :parent_id, references(:conditional_parents)
            end
          end
        end
        """
      )

      expected_resources = %{
        "conditional_children" => {nil, OfficeGraph.Tenancy.Organization},
        "conditional_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "conditional_children.parent_id references conditional_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "removes foreign keys when a table is conditionally dropped and recreated" do
    in_migration_root("office_graph_conditional_foreign_key_drop", fn root, migrations ->
      _ = root

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

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == []
    end)
  end

  test "removes inbound foreign keys when a destination table is dropped with cascade" do
    in_migration_root("office_graph_cascading_destination_drop", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:cascade_parents)

            create table(:cascade_children) do
              add :parent_id, references(:cascade_parents)
            end
          end
        end
        """
      )

      File.write!(
        Path.join(migrations, "20260731000001_drop_parents.exs"),
        """
        defmodule DropParents do
          use Ecto.Migration

          def change do
            drop table(:cascade_parents), mode: :cascade
          end
        end
        """
      )

      File.write!(
        Path.join(migrations, "20260731000002_recreate_parents.exs"),
        """
        defmodule RecreateParents do
          use Ecto.Migration

          def change do
            create table(:cascade_parents)
          end
        end
        """
      )

      expected_resources = %{
        "cascade_children" => {nil, OfficeGraph.Tenancy.Organization},
        "cascade_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == []
    end)
  end

  test "resolves migration module attributes at each definition site" do
    in_migration_root("office_graph_module_attribute_migration_conformance", fn root,
                                                                                migrations ->
      _ = root

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

  test "resolves module-scope bindings before storing migration attributes" do
    in_migration_root("office_graph_bound_module_attribute_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          table_name = :bound_attribute_parents
          @parent_table table_name

          table_name = :bound_attribute_children
          @child_table table_name

          def change do
            create table(@parent_table)

            create table(@child_table) do
              add :parent_id, references(@parent_table)
            end
          end
        end
        """
      )

      expected_resources = %{
        "bound_attribute_children" => {nil, OfficeGraph.Tenancy.Organization},
        "bound_attribute_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_tables() == [
               "bound_attribute_children",
               "bound_attribute_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "bound_attribute_children.parent_id references bound_attribute_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "resolves aliases when selecting the owning migration module" do
    in_migration_root("office_graph_aliased_migration_module_conformance", fn root, migrations ->
      _ = root

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

  test "discovers a single migration module nested under a namespace" do
    in_migration_root("office_graph_nested_migration_module_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_nested_examples.exs"),
        """
        defmodule OfficeGraph.Migrations do
          defmodule CreateNestedExamples do
            use Ecto.Migration

            def change do
              create table(:nested_parents)

              create table(:nested_children) do
                add :parent_id, references(:nested_parents)
              end
            end
          end
        end
        """
      )

      expected_resources = %{
        "nested_children" => {nil, OfficeGraph.Tenancy.Organization},
        "nested_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_tables() == [
               "nested_children",
               "nested_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "nested_children.parent_id references nested_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "rejects migration files with multiple recognized migration modules" do
    in_migration_root("office_graph_multiple_migration_module_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_ambiguous_examples.exs"),
        """
        defmodule CreateFirstExamples do
          use Ecto.Migration

          def change do
            create table(:first_examples)
          end
        end

        defmodule CreateSecondExamples do
          use Ecto.Migration

          def change do
            create table(:second_examples)
          end
        end
        """
      )

      assert_raise ArgumentError, ~r/exactly one recognized migration module/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "rejects unsupported Enum control flow in migration entrypoints" do
    in_migration_root("office_graph_enum_callback_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260809000000_create_enum_examples.exs"),
        """
        defmodule CreateEnumExamples do
          use Ecto.Migration

          def change do
            Enum.each([:enum_parents, :enum_children], fn name ->
              create table(name)
            end)
          end
        end
        """
      )

      assert_raise ArgumentError, ~r/cannot statically verify migration Enum.each\/2/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "fails closed when a migration-like module uses an unrecognized wrapper" do
    in_migration_root("office_graph_wrapped_migration_conformance", fn root, migrations ->
      wrapper = Path.join(root, "lib/my_app/migration.ex")
      File.mkdir_p!(Path.dirname(wrapper))

      File.write!(
        wrapper,
        """
        defmodule MyApp.Migration do
          defmacro __using__(_options) do
            quote do
              use Ecto.Migration
            end
          end
        end
        """
      )

      File.write!(
        Path.join(migrations, "20260806000000_create_wrapped.exs"),
        """
        defmodule CreateWrapped do
          use MyApp.Migration

          def change do
            create table(:wrapped_examples)
          end
        end
        """
      )

      assert_raise ArgumentError, ~r/cannot statically verify migration module/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "normalizes qualified and aliased migration lifecycle calls" do
    in_migration_root("office_graph_qualified_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          alias Ecto.Migration, as: Migration
          use Migration

          def change do
            Ecto.Migration.create(Ecto.Migration.table(:qualified_parents))

            Migration.create(Migration.table(:qualified_children)) do
              Migration.add(:parent_id, Migration.references(:qualified_parents))
            end
          end
        end
        """
      )

      expected_resources = %{
        "qualified_children" => {nil, OfficeGraph.Tenancy.Organization},
        "qualified_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_tables() == [
               "qualified_children",
               "qualified_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "qualified_children.parent_id references qualified_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "normalizes migration lifecycle calls through static apply entrypoints" do
    in_migration_root("office_graph_static_apply_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          alias Ecto.Migration, as: Migration
          use Migration

          def change do
            apply(Ecto.Migration, :create, [table(:static_apply_parents)])
            Kernel.apply(Migration, :create, [table(:static_apply_children)])
            :erlang.apply(Ecto.Migration, :create, [table(:static_apply_erlang)])
            apply(Ecto.Migration, :create, [table(:static_apply_removed)])
            apply(Ecto.Migration, :drop, [table(:static_apply_removed)])
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == [
               "static_apply_children",
               "static_apply_erlang",
               "static_apply_parents"
             ]
    end)
  end

  test "does not normalize a shadowed local apply function as migration lifecycle" do
    in_migration_root("office_graph_local_apply_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            apply(Ecto.Migration, :create, [table(:not_created)])
          end

          defp apply(_receiver, _operation, _arguments), do: :ok
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == []
    end)
  end

  test "normalizes piped migration lifecycle and foreign-key calls" do
    in_migration_root("office_graph_piped_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            table(:piped_parents) |> create()

            table(:piped_children) |> create() do
              add :parent_id, references(:piped_parents)
            end

            table(:piped_removed) |> create()
            table(:piped_removed) |> drop()
          end
        end
        """
      )

      expected_resources = %{
        "piped_children" => {nil, OfficeGraph.Tenancy.Organization},
        "piped_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_tables() == [
               "piped_children",
               "piped_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "piped_children.parent_id references piped_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "preserves binary table names across migration ownership operations" do
    in_migration_root("office_graph_binary_table_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table("binary_old_parents")
            rename table("binary_old_parents"), to: table("binary_parents")

            create table("binary_children") do
              add :parent_id, references("binary_parents")
            end

            create table("binary_removed")
            drop table("binary_removed")
          end
        end
        """
      )

      expected_resources = %{
        "binary_children" => {nil, OfficeGraph.Tenancy.Organization},
        "binary_parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert MigrationConformanceSupport.migration_tables() == [
               "binary_children",
               "binary_parents"
             ]

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "binary_children.parent_id references binary_parents.id without a matching belongs_to"
             ]
    end)
  end

  test "preserves table prefixes in migration ownership identities" do
    in_migration_root("office_graph_prefixed_migration_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:events)
            create table(:events, prefix: "audit")
          end
        end
        """
      )

      assert MigrationConformanceSupport.migration_tables() == ["audit.events", "events"]
    end)
  end

  test "compares prefixed migration foreign keys with Ash resource schemas" do
    in_migration_root("office_graph_prefixed_foreign_key_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents, prefix: "audit")

            create table(:children, prefix: "audit") do
              add :parent_id, references(:parents)
            end
          end
        end
        """
      )

      expected_resources = %{
        "children" => {nil, MigrationConformanceSupport.AuditChildResource},
        "parents" => {nil, MigrationConformanceSupport.AuditParentResource}
      }

      assert MigrationConformanceSupport.migration_foreign_key_relationship_errors(
               expected_resources
             ) == [
               "audit.children.parent_id references audit.parents.id without a matching belongs_to"
             ]
    end)
  end

  test "rejects table prefixes that cannot be resolved statically" do
    in_migration_root("office_graph_dynamic_prefix_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            prefix = configured_prefix()
            create table(:events, prefix: prefix)
          end

          defp configured_prefix, do: System.fetch_env!("EVENT_SCHEMA")
        end
        """
      )

      assert_raise ArgumentError, ~r/cannot statically resolve migration table prefix/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "rejects table identities that cannot be resolved statically" do
    in_migration_root("office_graph_dynamic_table_identity_conformance", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            name = System.get_env("TABLE", "durable")
            create table(name)
          end
        end
        """
      )

      assert_raise ArgumentError, ~r/cannot statically resolve migration table identity/, fn ->
        MigrationConformanceSupport.migration_tables()
      end
    end)
  end

  test "rejects unresolved table identities in foreign-key inventory" do
    [
      {"source",
       """
       alter table(configured_table()) do
         add :parent_id, references(:parents)
       end
       """},
      {"destination",
       """
       create table(:children) do
         add :parent_id, references(configured_table())
       end
       """}
    ]
    |> Enum.each(fn {identity_position, migration_operation} ->
      in_migration_root(
        "office_graph_dynamic_#{identity_position}_identity_conformance",
        fn root, migrations ->
          _ = root

          File.write!(
            Path.join(migrations, "20260731000000_create_examples.exs"),
            """
            defmodule CreateExamples do
              use Ecto.Migration

              def change do
                create table(:parents)
                #{migration_operation}
              end

              defp configured_table, do: System.get_env("TABLE", "children")
            end
            """
          )

          assert_raise ArgumentError,
                       ~r/cannot statically resolve migration table identity/,
                       fn ->
                         MigrationConformanceSupport.migration_foreign_key_relationship_errors(
                           %{}
                         )
                       end
        end
      )
    end)
  end

  test "rejects reference prefixes that cannot be resolved statically" do
    in_migration_root("office_graph_dynamic_reference_prefix", fn root, migrations ->
      _ = root

      File.write!(
        Path.join(migrations, "20260731000000_create_examples.exs"),
        """
        defmodule CreateExamples do
          use Ecto.Migration

          def change do
            create table(:parents)

            create table(:children) do
              add :parent_id, references(:parents, prefix: configured_prefix())
            end
          end

          defp configured_prefix, do: System.fetch_env!("EVENT_SCHEMA")
        end
        """
      )

      expected_resources = %{
        "children" => {nil, OfficeGraph.Tenancy.Organization},
        "parents" => {nil, OfficeGraph.Tenancy.Workspace}
      }

      assert_raise ArgumentError, ~r/cannot statically resolve migration table prefix/, fn ->
        MigrationConformanceSupport.migration_foreign_key_relationship_errors(expected_resources)
      end
    end)
  end

  defp in_migration_root(label, fun) when is_binary(label) and is_function(fun, 2) do
    root =
      Path.join(
        System.tmp_dir!(),
        "#{label}_#{System.unique_integer([:positive])}"
      )

    migrations = Path.join(root, "priv/repo/migrations")
    File.mkdir_p!(migrations)
    on_exit(fn -> File.rm_rf!(root) end)

    File.cd!(root, fn -> fun.(root, migrations) end)
  end
end
