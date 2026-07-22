snapshot_lineage_migration_path =
  Application.app_dir(
    :office_graph,
    "priv/repo/migrations/20260722040000_harden_agent_runtime_snapshot_lineage.exs"
  )

if File.exists?(snapshot_lineage_migration_path) and
     not Code.ensure_loaded?(OfficeGraph.Repo.Migrations.HardenAgentRuntimeSnapshotLineage) do
  Code.require_file(snapshot_lineage_migration_path)
end

defmodule OfficeGraph.AgentRuntime.SnapshotLineageMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Repo

  alias OfficeGraph.AgentRuntime.{
    Authority,
    AuthoritySnapshot
  }

  alias OfficeGraph.Repo.Migrations.HardenAgentRuntimeSnapshotLineage
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  test "rehashes pre-existing authority snapshots after adapter lineage is backfilled" do
    context = AgentRuntimeSupport.invocation_fixture()
    invoked = AgentRuntimeSupport.invoke_human(context)
    snapshot = invoked.authority_snapshot

    Repo.query!(
      "UPDATE agent_authority_snapshots SET authority_hash = $1 WHERE id = $2",
      ["pre-adapter-lineage-hash", Ecto.UUID.dump!(snapshot.id)]
    )

    assert {:error, :authority_snapshot_invalid} = Authority.revalidate(invoked.execution.id)

    assert :ok = HardenAgentRuntimeSnapshotLineage.rehash_authority_snapshots(Repo)
    assert :ok = Authority.revalidate(invoked.execution.id)

    rehashed = Ash.get!(AuthoritySnapshot, snapshot.id, authorize?: false)
    assert rehashed.authority_hash == Authority.authority_hash(Map.from_struct(rehashed))
  end
end
