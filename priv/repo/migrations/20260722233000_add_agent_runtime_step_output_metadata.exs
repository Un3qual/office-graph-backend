defmodule OfficeGraph.Repo.Migrations.AddAgentRuntimeStepOutputMetadata do
  use Ecto.Migration

  def change do
    alter table(:agent_model_requests) do
      add :output_safe_summary, :text
    end

    alter table(:agent_tool_requests) do
      add :output_reference, :text
      add :output_content_hash, :text
      add :output_byte_count, :bigint
    end

    create constraint(:agent_tool_requests, :agent_tool_requests_reference_metadata_complete,
             check: """
             (output_reference IS NULL AND output_content_hash IS NULL AND output_byte_count IS NULL)
             OR
             (output_reference IS NOT NULL AND output_content_hash IS NOT NULL AND output_byte_count > 0)
             """
           )
  end
end
