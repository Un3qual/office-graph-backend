defmodule OfficeGraph.Architecture.AshConformanceTest do
  use ExUnit.Case, async: true

  @ash_domain OfficeGraph.WorkGraph.Domain

  @required_resources [
    OfficeGraph.WorkGraph.Resources.Signal,
    OfficeGraph.WorkGraph.Resources.Task,
    OfficeGraph.WorkGraph.Resources.ReviewFinding,
    OfficeGraph.WorkGraph.Resources.VerificationCheck,
    OfficeGraph.WorkGraph.Resources.Artifact,
    OfficeGraph.WorkGraph.Resources.EvidenceItem,
    OfficeGraph.WorkGraph.Resources.VerificationResult
  ]

  @approved_direct_repo_mutation_functions %{
    "lib/office_graph/work_graph.ex" =>
      MapSet.new([
        "create_signal/3",
        "create_task/4",
        "create_review_finding/4",
        "create_verification_check/4",
        "complete_verification/4",
        "transaction_result/5"
      ]),
    "lib/office_graph/integrations.ex" =>
      MapSet.new(["record_manual_intake/3", "get_or_insert!/3"]),
    "lib/office_graph/operations.ex" => MapSet.new(["start_operation/3"]),
    "lib/office_graph/audit.ex" => MapSet.new(["record!/5"]),
    "lib/office_graph/revisions.ex" => MapSet.new(["record!/5"]),
    "lib/office_graph/identity.ex" =>
      MapSet.new(["ensure_owner/1", "ensure_session_context/3", "get_or_insert!/3"]),
    "lib/office_graph/tenancy.ex" => MapSet.new(["ensure_local_scope/1", "get_or_insert!/3"]),
    "lib/office_graph/authorization.ex" =>
      MapSet.new(["ensure_owner_role/2", "get_or_insert!/3"]),
    "lib/office_graph/proposed_changes.ex" =>
      MapSet.new(["create_for_manual_intake/4", "reject!/2", "mark_applied!/1"]),
    "lib/office_graph/content.ex" => MapSet.new(["create_plain_document/3"])
  }

  test "work graph has an Ash domain and required Ash resources" do
    assert Code.ensure_loaded?(@ash_domain),
           "#{inspect(@ash_domain)} is not loaded; define the WorkGraph Ash domain before this conformance test can pass"

    for resource <- @required_resources do
      assert Code.ensure_loaded?(resource),
             "#{inspect(resource)} is not loaded; define the required WorkGraph Ash resource before this conformance test can pass"

      assert Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer,
             "#{inspect(resource)} must use AshPostgres.DataLayer"
    end
  end

  test "work graph Ash domain registers the required resources" do
    assert Code.ensure_loaded?(@ash_domain),
           "#{inspect(@ash_domain)} is not loaded; cannot inspect registered Ash resources"

    registered =
      @ash_domain
      |> Ash.Domain.Info.resources()
      |> MapSet.new()

    missing =
      @required_resources
      |> MapSet.new()
      |> MapSet.difference(registered)
      |> MapSet.to_list()

    assert missing == [],
           "WorkGraph Ash domain is missing required resources: #{inspect(missing)}"
  end

  test "direct Repo mutation paths are explicitly allowlisted" do
    unapproved =
      Enum.reject(direct_repo_mutations(), fn mutation ->
        mutation.function in Map.get(
          @approved_direct_repo_mutation_functions,
          mutation.path,
          MapSet.new()
        )
      end)

    assert unapproved == [],
           "Found direct Repo/Ecto.Multi mutations outside approved functions:\n#{inspect(unapproved, pretty: true)}"
  end

  defp direct_repo_mutations do
    mutation_pattern =
      ~r/((?:OfficeGraph\.)?Repo\.(insert!?|insert_all|update!?|update_all|delete!?|delete_all|insert_or_update!|insert_or_update|transaction)\b|(?:Ecto\.)?Multi\.(insert|insert_all|update|update_all|delete|delete_all|insert_or_update!|insert_or_update)\b)/

    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn path -> scan_file_for_mutations(path, mutation_pattern) end)
  end

  defp scan_file_for_mutations(path, mutation_pattern) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({nil, []}, fn {line, line_number}, {current_function, matches} ->
      current_function = function_name(line) || current_function

      if String.match?(line, mutation_pattern) do
        mutation = %{
          path: path,
          line: line_number,
          function: current_function,
          source: String.trim(line)
        }

        {current_function, [mutation | matches]}
      else
        {current_function, matches}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp function_name(line) do
    case Regex.run(~r/^\s*defp?\s+([a-zA-Z0-9_!?]+)\((.*)\)\s+do/, line) do
      [_, name, args] -> "#{name}/#{arity(args)}"
      _ -> nil
    end
  end

  defp arity(args) do
    args
    |> String.trim()
    |> case do
      "" -> 0
      args -> args |> String.split(",") |> length()
    end
  end
end
