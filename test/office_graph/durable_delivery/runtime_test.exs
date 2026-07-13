defmodule OfficeGraph.DurableDelivery.RuntimeTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Repo

  test "Oban is configured as the Postgres-backed durable runtime" do
    assert Code.ensure_loaded?(Oban)

    config = Application.fetch_env!(:office_graph, Oban)

    assert config[:repo] == Repo
    assert config[:testing] == :manual
    assert config[:queues] == false
    assert config[:plugins] == false
  end

  test "production retains terminal jobs for the operator history window" do
    production_config = Config.Reader.read!("config/config.exs", env: :prod)
    oban_config = production_config[:office_graph][Oban]

    assert {Oban.Plugins.Pruner, pruner_options} =
             Enum.find(oban_config[:plugins], fn
               {plugin, _options} -> plugin == Oban.Plugins.Pruner
               plugin -> plugin == Oban.Plugins.Pruner
             end)

    assert pruner_options[:max_age] == 30 * 24 * 60 * 60
  end

  test "durable runtime tables preserve typed event and job state" do
    assert table_exists?("oban_jobs")
    assert table_exists?("domain_events")

    assert MapSet.new(domain_event_columns()) ==
             MapSet.new([
               "id",
               "organization_id",
               "workspace_id",
               "operation_id",
               "causation_event_id",
               "event_key",
               "event_kind",
               "subject_kind",
               "subject_id",
               "subject_version",
               "delivery_state",
               "failure_code",
               "occurred_at",
               "dispatched_at",
               "failed_at",
               "inserted_at",
               "updated_at"
             ])

    assert index_exists?("domain_events_event_key_index")
    assert index_exists?("domain_events_scope_state_occurred_at_index")
    assert index_exists?("domain_events_operation_id_index")
    assert index_exists?("domain_events_subject_index")
  end

  defp table_exists?(table_name) do
    %{rows: [[exists?]]} =
      Ecto.Adapters.SQL.query!(Repo, "SELECT to_regclass($1) IS NOT NULL", [table_name])

    exists?
  end

  defp domain_event_columns do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'domain_events'
        ORDER BY ordinal_position
        """,
        []
      )

    Enum.map(rows, fn [column] -> column end)
  end

  defp index_exists?(index_name) do
    %{rows: [[exists?]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND indexname = $1)",
        [index_name]
      )

    exists?
  end
end
