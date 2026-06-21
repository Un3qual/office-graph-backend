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

  @approved_direct_repo_mutation_files %{
    "lib/office_graph/work_graph.ex" => [
      "graph identity and graph relationship writes stay in one explicit Ecto transaction"
    ],
    "lib/office_graph/integrations.ex" => [
      "raw archive and replay/idempotency storage are approved direct Ecto paths"
    ],
    "lib/office_graph/operations.ex" => [
      "operation correlation creation is the shared operation spine"
    ],
    "lib/office_graph/audit.ex" => [
      "audit append writes are a shared side-effect contract"
    ],
    "lib/office_graph/revisions.ex" => [
      "revision append writes are a shared side-effect contract"
    ],
    "lib/office_graph/identity.ex" => [
      "local bootstrap identity path is accepted for the walking skeleton"
    ],
    "lib/office_graph/tenancy.ex" => [
      "local bootstrap tenancy path is accepted for the walking skeleton"
    ],
    "lib/office_graph/authorization.ex" => [
      "local bootstrap authorization path is accepted for the walking skeleton"
    ],
    "lib/office_graph/proposed_changes.ex" => [
      "proposed-change review ledger is an orchestration table for the skeleton"
    ],
    "lib/office_graph/content.ex" => [
      "rich-text v1 document/block creation remains a narrowed Ecto path until the content domain is Ash-backed"
    ]
  }

  test "work graph has an Ash domain and required Ash resources" do
    assert Code.ensure_loaded?(@ash_domain)

    for resource <- @required_resources do
      assert Code.ensure_loaded?(resource), "#{inspect(resource)} is not loaded"
      assert Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer
    end
  end

  test "work graph Ash domain registers the required resources" do
    assert Code.ensure_loaded?(@ash_domain)

    registered =
      @ash_domain
      |> Ash.Domain.Info.resources()
      |> MapSet.new()

    assert MapSet.subset?(MapSet.new(@required_resources), registered)
  end

  test "direct Repo mutation paths are explicitly allowlisted" do
    repo_mutation_pattern =
      ~r/(Repo\.(insert!?|update!?|delete!?|transaction)\b|Ecto\.Multi\.(insert|update|delete)\b)/

    actual =
      "lib/office_graph/**/*.ex"
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        path
        |> File.read!()
        |> String.match?(repo_mutation_pattern)
      end)
      |> Enum.sort()

    assert actual -- Map.keys(@approved_direct_repo_mutation_files) == []
  end
end
