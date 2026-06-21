defmodule OfficeGraph.Integrations.ConcurrencyTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.{Integrations, Operations, Repo}

  test "first manual intakes sharing a new source survive the source creation race" do
    suffix = System.unique_integer([:positive])
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()
    principal_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()
    source_identity = "manual:source-race-#{suffix}"

    session_context = %SessionContext{
      principal_id: principal_id,
      session_id: session_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(["manual_intake.submit"])
    }

    try do
      with_unboxed_connection(fn ->
        install_source_insert_barrier!()

        insert_minimal_session_scope!(
          organization_id,
          workspace_id,
          principal_id,
          session_id,
          suffix
        )
      end)

      results =
        ["first", "second"]
        |> Enum.map(fn replay_identity ->
          Task.async(fn ->
            with_unboxed_connection(fn ->
              submit_manual_intake(session_context, source_identity, replay_identity)
            end)
          end)
        end)
        |> Task.await_many(10_000)

      assert [
               {:ok, %{duplicate?: false, normalized_event: %{outcome: "accepted"}}},
               {:ok, %{duplicate?: false, normalized_event: %{outcome: "accepted"}}}
             ] = results

      source_ids =
        results
        |> Enum.map(fn {:ok, intake} -> intake.raw_archive.source_id end)
        |> Enum.uniq()

      assert length(source_ids) == 1
    after
      with_unboxed_connection(fn ->
        cleanup_committed_scope!(organization_id, principal_id, source_identity)
        drop_source_insert_barrier!()
      end)
    end
  end

  defp submit_manual_intake(session_context, source_identity, replay_identity) do
    with {:ok, operation} <-
           Operations.start_operation(session_context, :manual_intake_submit,
             correlation_id: "source-race-#{replay_identity}"
           ) do
      Integrations.submit_manual_intake(session_context, operation, %{
        source_identity: source_identity,
        replay_identity: "paste:#{replay_identity}",
        body: "Task: verify concurrent manual intake source creation #{replay_identity}"
      })
    end
  end

  defp with_unboxed_connection(fun) do
    checkout = Sandbox.checkout(Repo, sandbox: false)

    try do
      fun.()
    after
      if checkout == :ok do
        Sandbox.checkin(Repo)
      end
    end
  end

  defp insert_minimal_session_scope!(
         organization_id,
         workspace_id,
         principal_id,
         session_id,
         suffix
       ) do
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO organizations (id, name, slug, inserted_at, updated_at)
      VALUES ($1::uuid, $2, $3, $4, $4)
      """,
      [db_uuid(organization_id), "Race Org #{suffix}", "race-org-#{suffix}", now]
    )

    Repo.query!(
      """
      INSERT INTO workspaces (id, organization_id, name, slug, inserted_at, updated_at)
      VALUES ($1::uuid, $2::uuid, $3, $4, $5, $5)
      """,
      [
        db_uuid(workspace_id),
        db_uuid(organization_id),
        "Race Workspace #{suffix}",
        "race-workspace-#{suffix}",
        now
      ]
    )

    Repo.query!(
      """
      INSERT INTO principals (id, email, kind, status, inserted_at, updated_at)
      VALUES ($1::uuid, $2, 'human', 'active', $3, $3)
      """,
      [db_uuid(principal_id), "race-#{suffix}@office-graph.local", now]
    )

    Repo.query!(
      """
      INSERT INTO sessions (
        id,
        principal_id,
        organization_id,
        workspace_id,
        purpose,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'source_race', $5, $5)
      """,
      [
        db_uuid(session_id),
        db_uuid(principal_id),
        db_uuid(organization_id),
        db_uuid(workspace_id),
        now
      ]
    )
  end

  defp install_source_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_source_race_barrier ON external_sources"
    )

    Repo.query!("""
    CREATE OR REPLACE FUNCTION office_graph_test_source_race_barrier()
    RETURNS trigger AS $$
    DECLARE
      source_hash integer := hashtext(NEW.key);
      started_at timestamp := clock_timestamp();
    BEGIN
      IF NEW.key LIKE 'manual:source-race-%' THEN
        IF pg_try_advisory_lock(91001, source_hash) THEN
          LOOP
            IF pg_try_advisory_lock(91002, source_hash) THEN
              PERFORM pg_advisory_unlock(91002, source_hash);
              EXIT WHEN clock_timestamp() - started_at > interval '2 seconds';
              PERFORM pg_sleep(0.01);
            ELSE
              EXIT;
            END IF;
          END LOOP;

          PERFORM pg_advisory_unlock(91001, source_hash);
        ELSE
          PERFORM pg_advisory_lock(91002, source_hash);
          PERFORM pg_sleep(0.05);
          PERFORM pg_advisory_unlock(91002, source_hash);
        END IF;
      END IF;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER office_graph_test_source_race_barrier
    BEFORE INSERT ON external_sources
    FOR EACH ROW
    EXECUTE FUNCTION office_graph_test_source_race_barrier()
    """)
  end

  defp cleanup_committed_scope!(organization_id, principal_id, source_identity) do
    Repo.query!("DELETE FROM proposed_graph_changes WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM normalized_intake_events WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM raw_archives WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM external_sources WHERE key = $1", [source_identity])

    Repo.query!("DELETE FROM operation_correlations WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM sessions WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM workspaces WHERE organization_id = $1::uuid", [
      db_uuid(organization_id)
    ])

    Repo.query!("DELETE FROM principals WHERE id = $1::uuid", [db_uuid(principal_id)])
    Repo.query!("DELETE FROM organizations WHERE id = $1::uuid", [db_uuid(organization_id)])
  end

  defp drop_source_insert_barrier! do
    Repo.query!(
      "DROP TRIGGER IF EXISTS office_graph_test_source_race_barrier ON external_sources"
    )

    Repo.query!("DROP FUNCTION IF EXISTS office_graph_test_source_race_barrier()")
  end

  defp db_uuid(uuid), do: Ecto.UUID.dump!(uuid)
end
