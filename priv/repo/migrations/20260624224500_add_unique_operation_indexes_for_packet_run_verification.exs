defmodule OfficeGraph.Repo.Migrations.AddUniqueOperationIndexesForPacketRunVerification do
  use Ecto.Migration

  def change do
    create unique_index(:work_packets, [:operation_id],
             where: "operation_id IS NOT NULL",
             name: :work_packets_operation_id_unique_index
           )

    create unique_index(:runs, [:operation_id],
             where: "operation_id IS NOT NULL",
             name: :runs_operation_id_unique_index
           )

    create unique_index(:execution_observations, [:operation_id],
             name: :execution_observations_operation_id_unique_index
           )

    create unique_index(:evidence_candidates, [:operation_id],
             name: :evidence_candidates_operation_id_unique_index
           )

    create unique_index(:evidence_items, [:acceptance_operation_id],
             where: "acceptance_operation_id IS NOT NULL",
             name: :evidence_items_acceptance_operation_id_unique_index
           )
  end
end
