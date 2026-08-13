defmodule OfficeGraph.ProjectQuality.DatabaseStructuralGateTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.ProjectQuality.DatabaseStructuralGate

  test "reconciles a compiler import only with an explicit source target" do
    source = [occurrence(:source)]
    compiled = [occurrence(:compiled)]

    assert DatabaseStructuralGate.compiled_diagnostics(source, compiled) == []
  end

  test "rejects a compiler import hidden behind source indirection" do
    [diagnostic] = DatabaseStructuralGate.compiled_diagnostics([], [occurrence(:compiled)])

    assert diagnostic.kind == :compiled_reference
    assert diagnostic.path == "lib/example.ex"
    assert diagnostic.construct == "Repo.all"
    assert diagnostic.target_module == "OfficeGraph.Repo"
    assert diagnostic.target_function == :all
    assert diagnostic.target_arity == 1
  end

  test "current repository satisfies the additive structural gate" do
    assert DatabaseStructuralGate.check_repository(File.cwd!()) == []
  end

  defp occurrence(kind) do
    %{
      path: "lib/example.ex",
      line: 1,
      function: nil,
      caller: "Example",
      class: :direct_ecto,
      construct: "Repo.all",
      target_module: "OfficeGraph.Repo",
      target_function: :all,
      target_arity: 1,
      ordinal: 1,
      fingerprint: "sha256:#{kind}",
      approval: kind
    }
  end
end
