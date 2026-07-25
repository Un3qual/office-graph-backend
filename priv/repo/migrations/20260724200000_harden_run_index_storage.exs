defmodule OfficeGraph.Repo.Migrations.HardenRunIndexStorage do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE runs
    SET
      aggregate_state = COALESCE(aggregate_state, 'unknown'),
      execution_state = COALESCE(execution_state, 'unknown'),
      verification_state = COALESCE(verification_state, 'unknown')
    WHERE aggregate_state IS NULL
       OR execution_state IS NULL
       OR verification_state IS NULL
    """)

    alter table(:runs) do
      modify :aggregate_state, :text, null: false
      modify :execution_state, :text, null: false
      modify :verification_state, :text, null: false
    end
  end

  def down do
    alter table(:runs) do
      modify :aggregate_state, :text, null: true
      modify :execution_state, :text, null: true
      modify :verification_state, :text, null: true
    end
  end
end
