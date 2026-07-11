defmodule OfficeGraph.Repo.Migrations.AllowWaivedVerificationResults do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE verification_results
    ALTER COLUMN evidence_item_id DROP NOT NULL
    """
  end

  def down do
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1
        FROM verification_results
        WHERE evidence_item_id IS NULL
      ) THEN
        RAISE EXCEPTION 'cannot restore verification_results.evidence_item_id NOT NULL while waived rows exist';
      END IF;
    END
    $$
    """

    execute """
    ALTER TABLE verification_results
    ALTER COLUMN evidence_item_id SET NOT NULL
    """
  end
end
