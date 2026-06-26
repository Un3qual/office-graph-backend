defmodule OfficeGraph.Repo.Migrations.DropLegacyVerificationResultCheckIndex do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:verification_results, [:verification_check_id],
                     name: :verification_results_verification_check_id_index
                   )
  end

  def down do
    :ok
  end
end
