defmodule OfficeGraph.Integrations.CommandReplayConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  test "operation idempotency keys are race safe" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    idempotency_key = "operation-race-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    try do
      with_unboxed_connection(fn ->
        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )

        install_operation_insert_barrier!()
      end)

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              Operations.start_operation(session_context, :manual_intake_submit,
                idempotency_key: idempotency_key
              )
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.id == second.id

      assert 1 ==
               with_unboxed_connection(fn ->
                 operation_idempotency_count(organization_id, idempotency_key)
               end)
    after
      with_unboxed_connection(fn ->
        drop_operation_insert_barrier!()
        cleanup_committed_scope!(organization_id, principal_id, [])
      end)
    end
  end

  test "operation idempotency keys do not reuse another caller's operation" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    other_principal_id = Ecto.UUID.generate()
    other_session_id = Ecto.UUID.generate()
    idempotency_key = "operation-caller-scope-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    other_session_context = %SessionContext{
      principal_id: other_principal_id,
      session_id: other_session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    try do
      with_unboxed_connection(fn ->
        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )

        insert_additional_session_in_scope!(
          organization_id,
          workspace_id,
          other_principal_id,
          other_session_id,
          suffix
        )

        assert {:ok, first} =
                 Operations.start_operation(session_context, :manual_intake_submit,
                   idempotency_key: idempotency_key
                 )

        assert {:ok, second} =
                 Operations.start_operation(other_session_context, :manual_intake_submit,
                   idempotency_key: idempotency_key
                 )

        assert first.id != second.id
        assert first.principal_id == principal_id
        assert second.principal_id == other_principal_id

        assert 2 == operation_idempotency_count(organization_id, idempotency_key)
      end)
    after
      with_unboxed_connection(fn ->
        cleanup_committed_scope!(organization_id, [principal_id, other_principal_id], [])
      end)
    end
  end

  test "work packet creation is idempotent under operation replay races" do
    suffix = System.unique_integer([:positive])
    organization_slug = "work-packet-create-race-#{suffix}"
    workspace_slug = "work-packet-create-race-workspace-#{suffix}"
    owner_email = "work-packet-create-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, packet_operation, attrs} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Work Packet Create Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Work Packet Create Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Work Packet Create Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "packet-#{suffix}")

          {:ok, packet_operation} =
            Operations.start_operation(bootstrap.session, :work_packet_create,
              idempotency_key: "work-packet-create-race-#{suffix}"
            )

          install_work_packet_insert_barrier!(packet_operation.id)

          attrs = %{
            title: "Concurrent packet #{suffix}",
            objective: "Create one packet for one operation.",
            context_summary: "Concurrent packet creation context.",
            requirements: "Serialize packet creation.",
            success_criteria: "Only one packet is created.",
            autonomy_posture: "human_supervised",
            source_graph_item_ids: [verification_check.graph_item_id],
            verification_check_ids: [verification_check.id]
          }

          {bootstrap, packet_operation, attrs}
        end)

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              WorkPackets.create_packet(bootstrap.session, packet_operation, attrs)
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.packet.id == second.packet.id
      assert first.version.id == second.version.id

      assert {1, 1} =
               with_unboxed_connection(fn ->
                 packet_creation_counts(packet_operation.id)
               end)
    after
      with_unboxed_connection(fn ->
        drop_work_packet_insert_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end

  test "work run creation is idempotent under operation replay races" do
    suffix = System.unique_integer([:positive])
    organization_slug = "work-run-create-race-#{suffix}"
    workspace_slug = "work-run-create-race-workspace-#{suffix}"
    owner_email = "work-run-create-race-#{suffix}@office-graph.local"

    try do
      {bootstrap, packet_version, run_operation} =
        with_unboxed_connection(fn ->
          {:ok, bootstrap} =
            Foundation.bootstrap_local_owner(
              organization_name: "Work Run Create Race #{suffix}",
              organization_slug: organization_slug,
              workspace_name: "Work Run Create Race Workspace #{suffix}",
              workspace_slug: workspace_slug,
              owner_email: owner_email,
              owner_name: "Work Run Create Race Owner"
            )

          {:ok, verification_check} =
            create_concurrency_verification_check(bootstrap.session, "run-#{suffix}")

          {:ok, packet_result} =
            create_concurrency_ready_packet(bootstrap.session, [verification_check], suffix)

          {:ok, run_operation} =
            Operations.start_operation(bootstrap.session, :work_run_start,
              idempotency_key: "work-run-create-race-#{suffix}"
            )

          install_work_run_insert_barrier!(run_operation.id)

          {bootstrap, packet_result.version, run_operation}
        end)

      attrs = %{
        source_surface: "concurrency_test",
        reason: "Create one run for one operation.",
        authority_posture: "human_supervised"
      }

      results =
        1..2
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              Runs.start_run(bootstrap.session, run_operation, packet_version, attrs)
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [{:ok, first}, {:ok, second}] = results
      assert first.run.id == second.run.id

      assert {1, 1} =
               with_unboxed_connection(fn ->
                 run_creation_counts(run_operation.id)
               end)
    after
      with_unboxed_connection(fn ->
        drop_work_run_insert_barrier!()
        cleanup_work_run_verification_scope!(organization_slug)
        cleanup_bootstrap_scope!(organization_slug, owner_email)
      end)
    end
  end
end
