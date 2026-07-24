defmodule OfficeGraph.Projections.OperatorRunIndexTest do
  use OfficeGraph.TestSupport.OperatorProjectionSupport

  test "returns newest-first safe run summaries with packet labels" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)
    {:ok, older} = create_ready_run(bootstrap.session, verification_check)
    {:ok, newer} = create_ready_run(bootstrap.session, verification_check)

    set_run_inserted_at!(older.run.id, ~U[2026-07-20 10:00:00.000000Z])
    set_run_inserted_at!(newer.run.id, ~U[2026-07-20 11:00:00.000000Z])

    packet =
      Ash.get!(OfficeGraph.WorkPackets.WorkPacket, newer.run.work_packet_id, authorize?: false)

    assert {:ok, page} =
             Projections.operator_runs_page(bootstrap.session, limit: 10, after_cursor: nil)

    assert Enum.map(page.row_edges, &elem(&1, 0).id) == [newer.run.id, older.run.id]

    {row, cursor: cursor} = hd(page.row_edges)
    assert is_binary(cursor)

    assert row == %{
             id: newer.run.id,
             objective: newer.run.objective,
             aggregate_state: newer.run.aggregate_state,
             execution_state: newer.run.execution_state,
             verification_state: newer.run.verification_state,
             inserted_at: ~U[2026-07-20 11:00:00.000000Z],
             source_watermark: row.source_watermark,
             packet: %{
               id: packet.id,
               title: packet.title,
               state: packet.state
             },
             packet_version: %{
               id: newer.packet_version.id,
               version_number: newer.packet_version.version_number,
               lifecycle_state: newer.packet_version.lifecycle_state,
               objective: newer.packet_version.objective
             }
           }

    assert is_binary(row.source_watermark)
    assert page.has_next_page? == false
    assert page.has_previous_page? == false
  end

  test "paginates without duplication and keeps continuation stable after a leading insert" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    runs =
      for index <- 1..3 do
        {:ok, result} = create_ready_run(bootstrap.session, verification_check)

        set_run_inserted_at!(
          result.run.id,
          DateTime.add(~U[2026-07-20 10:00:00Z], index, :second)
        )

        result
      end

    assert {:ok, first_page} =
             Projections.operator_runs_page(bootstrap.session, limit: 2, after_cursor: nil)

    assert Enum.map(first_page.row_edges, &elem(&1, 0).id) == [
             Enum.at(runs, 2).run.id,
             Enum.at(runs, 1).run.id
           ]

    assert first_page.has_next_page?

    {:ok, leading} = create_ready_run(bootstrap.session, verification_check)
    set_run_inserted_at!(leading.run.id, ~U[2026-07-20 12:00:00Z])

    {_last_row, cursor: cursor} = List.last(first_page.row_edges)

    assert {:ok, second_page} =
             Projections.operator_runs_page(bootstrap.session, limit: 2, after_cursor: cursor)

    assert Enum.map(second_page.row_edges, &elem(&1, 0).id) == [hd(runs).run.id]
    assert second_page.has_previous_page?
    refute second_page.has_next_page?
  end

  test "omits runs outside the resolved workspace and organization" do
    suffix = System.unique_integer([:positive])
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, local_check} = create_required_verification_check(bootstrap.session)
    {:ok, local_run} = create_ready_run(bootstrap.session, local_check)

    {:ok, other_workspace} =
      Foundation.bootstrap_local_owner(
        workspace_name: "Other workspace #{suffix}",
        workspace_slug: "other-workspace-#{suffix}",
        initiative_name: "Other initiative #{suffix}",
        initiative_slug: "other-initiative-#{suffix}"
      )

    {:ok, workspace_check} = create_required_verification_check(other_workspace.session)
    {:ok, workspace_run} = create_ready_run(other_workspace.session, workspace_check)

    {:ok, other_organization} =
      Foundation.bootstrap_local_owner(
        organization_name: "Other organization #{suffix}",
        organization_slug: "other-organization-#{suffix}",
        workspace_name: "Other organization workspace #{suffix}",
        workspace_slug: "other-organization-workspace-#{suffix}",
        initiative_name: "Other organization initiative #{suffix}",
        initiative_slug: "other-organization-initiative-#{suffix}",
        owner_email: "other-organization-#{suffix}@office-graph.local"
      )

    {:ok, organization_check} = create_required_verification_check(other_organization.session)
    {:ok, organization_run} = create_ready_run(other_organization.session, organization_check)

    assert {:ok, page} =
             Projections.operator_runs_page(bootstrap.session, limit: 10, after_cursor: nil)

    ids = Enum.map(page.row_edges, &elem(&1, 0).id)
    assert local_run.run.id in ids
    refute workspace_run.run.id in ids
    refute organization_run.run.id in ids
  end

  test "rejects a session without skeleton read and invalid pagination input" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    denied_session = create_session_with_capabilities!(bootstrap, [])

    assert {:error, :forbidden} =
             Projections.operator_runs_page(denied_session, limit: 1, after_cursor: nil)

    assert {:error, {:invalid_field, :after_cursor}} =
             Projections.operator_runs_page(bootstrap.session,
               limit: 1,
               after_cursor: "not-a-cursor"
             )

    assert {:error, {:invalid_field, :first}} =
             Projections.operator_runs_page(bootstrap.session, limit: -1, after_cursor: nil)
  end

  test "uses a constant number of batched reads as page result size grows" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, verification_check} = create_required_verification_check(bootstrap.session)

    for _index <- 1..3, do: create_ready_run(bootstrap.session, verification_check)

    {{:ok, small_page}, small_queries} =
      QueryCounter.count(fn ->
        Projections.operator_runs_page(bootstrap.session, limit: 3, after_cursor: nil)
      end)

    for _index <- 1..12, do: create_ready_run(bootstrap.session, verification_check)

    {{:ok, large_page}, large_queries} =
      QueryCounter.count(fn ->
        Projections.operator_runs_page(bootstrap.session, limit: 15, after_cursor: nil)
      end)

    assert length(small_page.row_edges) == 3
    assert length(large_page.row_edges) == 15
    assert length(large_queries) == length(small_queries)
    assert QueryCounter.source_count(large_queries, "runs") == 1
    assert QueryCounter.source_count(large_queries, "work_packets") == 1
    assert QueryCounter.source_count(large_queries, "work_packet_versions") == 1
  end

  defp set_run_inserted_at!(run_id, inserted_at) do
    Repo.query!("UPDATE runs SET inserted_at = $1, updated_at = $1 WHERE id = $2", [
      inserted_at,
      Ecto.UUID.dump!(run_id)
    ])
  end
end
