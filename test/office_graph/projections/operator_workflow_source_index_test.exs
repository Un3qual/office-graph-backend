unless Code.ensure_loaded?(OfficeGraph.Repo.Migrations.AddPacketSourceProjectionIndex) do
  Code.require_file(
    Application.app_dir(
      :office_graph,
      "priv/repo/migrations/20260712161500_add_packet_source_projection_index.exs"
    )
  )
end

defmodule OfficeGraph.Projections.OperatorWorkflowSourceIndexTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Operations
  alias OfficeGraph.OperatorCommandFixtures
  alias OfficeGraph.Repo
  alias OfficeGraph.Repo.Migrations.AddPacketSourceProjectionIndex
  alias OfficeGraph.WorkGraph

  @index_name "work_packet_version_sources_scope_graph_item_version_index"
  @migration_version 20_260_712_161_500

  test "packet source lookup index has the projection column order" do
    assert index_columns(@index_name) == [
             "organization_id",
             "workspace_id",
             "graph_item_id",
             "work_packet_version_id"
           ]
  end

  test "packet source lookup index migration is reversible" do
    run_migration!(:down)
    assert index_columns(@index_name) == []

    run_migration!(:up)

    assert index_columns(@index_name) == [
             "organization_id",
             "workspace_id",
             "graph_item_id",
             "work_packet_version_id"
           ]
  end

  @tag timeout: 120_000
  test "scoped graph item lookup uses the packet source projection index" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    {:ok, packet_result} =
      OperatorCommandFixtures.create_ready_packet(
        bootstrap.session,
        [verification_check],
        %{
          title: "Source index packet",
          objective: "Exercise scoped source lookup.",
          context_summary: "Representative planner cardinality.",
          requirements: "Use the scoped graph-item source index.",
          success_criteria: "The planner selects the projection index.",
          autonomy_posture: "human_supervised"
        }
      )

    insert_source_noise!(bootstrap, packet_result.version.id, 5_000)
    Repo.query!("ANALYZE work_packet_version_sources")

    plan =
      explain_plan(
        bootstrap.organization.id,
        bootstrap.workspace.id,
        verification_check.graph_item_id
      )

    assert Enum.any?(plan_nodes(plan), fn node ->
             node["Index Name"] == @index_name and
               node["Node Type"] in ["Index Scan", "Index Only Scan", "Bitmap Index Scan"]
           end)
  end

  defp create_required_verification_check(session) do
    {:ok, operation} = Operations.start_operation(session, :proposed_change_apply)

    with {:ok, %{signal: signal}} <-
           WorkGraph.create_signal(session, operation, %{
             title: "Source index signal",
             body: "Source index signal body."
           }),
         {:ok, %{task: task}} <-
           WorkGraph.create_task(session, operation, signal, %{
             title: "Source index task",
             body: "Source index task body."
           }),
         {:ok, %{review_finding: review_finding}} <-
           WorkGraph.create_review_finding(session, operation, task, %{
             title: "Source index finding",
             body: "Source index finding body."
           }),
         {:ok, %{verification_check: verification_check}} <-
           WorkGraph.create_verification_check(session, operation, review_finding, %{
             title: "Source index check",
             body: "Source index check body."
           }) do
      {:ok, verification_check}
    end
  end

  defp insert_source_noise!(bootstrap, version_id, count) do
    Repo.query!(
      """
      WITH inserted_items AS (
        INSERT INTO graph_items
          (id, organization_id, workspace_id, resource_type, resource_id, title,
           inserted_at, updated_at)
        SELECT gen_random_uuid(), $1, $2, 'source_index_probe', gen_random_uuid(),
               'Source index probe ' || series, now(), now()
        FROM generate_series(1, $4) AS series
        RETURNING id
      )
      INSERT INTO work_packet_version_sources
        (id, work_packet_version_id, graph_item_id, organization_id, workspace_id,
         source_kind, rationale, visibility, sensitivity, inserted_at, updated_at)
      SELECT gen_random_uuid(), $3, id, $1, $2, 'source_index_probe',
             'Representative source-index cardinality.', 'full', 'internal', now(), now()
      FROM inserted_items
      """,
      [
        Ecto.UUID.dump!(bootstrap.organization.id),
        Ecto.UUID.dump!(bootstrap.workspace.id),
        Ecto.UUID.dump!(version_id),
        count
      ]
    )
  end

  defp explain_plan(organization_id, workspace_id, graph_item_id) do
    %{rows: [[[plan]]]} =
      Repo.query!(
        """
        EXPLAIN (FORMAT JSON)
        SELECT work_packet_version_id
        FROM work_packet_version_sources
        WHERE organization_id = $1 AND workspace_id = $2 AND graph_item_id = $3
        """,
        [
          Ecto.UUID.dump!(organization_id),
          Ecto.UUID.dump!(workspace_id),
          Ecto.UUID.dump!(graph_item_id)
        ]
      )

    plan["Plan"]
  end

  defp plan_nodes(plan) do
    [plan | Enum.flat_map(Map.get(plan, "Plans", []), &plan_nodes/1)]
  end

  defp index_columns(index_name) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT attribute.attname
        FROM pg_class index_class
        JOIN pg_index index_meta ON index_meta.indexrelid = index_class.oid
        CROSS JOIN LATERAL unnest(index_meta.indkey)
          WITH ORDINALITY AS index_key(attnum, position)
        JOIN pg_attribute attribute
          ON attribute.attrelid = index_meta.indrelid
         AND attribute.attnum = index_key.attnum
        WHERE index_class.relname = $1
        ORDER BY index_key.position
        """,
        [index_name]
      )

    Enum.map(rows, &List.first/1)
  end

  defp run_migration!(direction) do
    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      @migration_version,
      AddPacketSourceProjectionIndex,
      :forward,
      direction,
      direction,
      log: false
    )
  end
end
