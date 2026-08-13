defmodule OfficeGraph.ProjectQuality.DatabaseDependencyAuditTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.DatabaseDependencyAudit

  test "reports compiler-resolved low-level module imports" do
    with_compiled_module(
      "lib/compiled_alias.ex",
      """
      defmodule CompiledAlias do
        alias OfficeGraph.Repo, as: Persistence
        def load(query), do: Persistence.all(query)
      end
      """,
      fn root, beams ->
        [occurrence] = DatabaseDependencyAudit.scan_paths(beams, root)

        assert Map.take(occurrence, [
                 :path,
                 :caller,
                 :target_module,
                 :target_function,
                 :target_arity,
                 :class
               ]) == %{
                 path: "lib/compiled_alias.ex",
                 caller: "CompiledAlias",
                 target_module: "OfficeGraph.Repo",
                 target_function: :all,
                 target_arity: 1,
                 class: :direct_ecto
               }
      end
    )
  end

  test "does not inspect generic callback imports" do
    with_compiled_module(
      "lib/generic.ex",
      """
      defmodule Generic do
        def run(fun, value), do: fun.(value)
      end
      """,
      fn root, beams ->
        assert DatabaseDependencyAudit.scan_paths(beams, root) == []
      end
    )
  end

  defp with_compiled_module(relative_path, source, fun) do
    root = Path.join(System.tmp_dir!(), "boundary-audit-#{System.unique_integer([:positive])}")
    source_path = Path.join(root, relative_path)
    beam_path = Path.join(root, "ebin")
    File.mkdir_p!(Path.dirname(source_path))
    File.mkdir_p!(beam_path)
    File.write!(source_path, source)

    try do
      assert {:ok, _modules, %{runtime_warnings: [], compile_warnings: []}} =
               Kernel.ParallelCompiler.compile_to_path([source_path], beam_path,
                 return_diagnostics: true
               )

      fun.(root, Path.wildcard(Path.join(beam_path, "*.beam")))
    after
      File.rm_rf!(root)
    end
  end
end
