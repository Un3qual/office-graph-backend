defmodule OfficeGraph.Repo.Migrations.AddPrincipalsNormalizedEmailIndex do
  use Ecto.Migration

  def up do
    execute("""
    CREATE INDEX principals_normalized_email_index
    ON principals (lower(btrim(email)))
    """)
  end

  def down do
    execute("DROP INDEX principals_normalized_email_index")
  end
end
