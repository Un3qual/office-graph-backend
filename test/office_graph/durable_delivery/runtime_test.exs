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
    production_config =
      Config.Reader.read!(Path.expand("../../../config/config.exs", __DIR__), env: :prod)

    oban_config = production_config[:office_graph][Oban]

    assert {Oban.Plugins.Pruner, pruner_options} =
             Enum.find(oban_config[:plugins], fn
               {plugin, _options} -> plugin == Oban.Plugins.Pruner
               plugin -> plugin == Oban.Plugins.Pruner
             end)

    assert pruner_options[:max_age] == 30 * 24 * 60 * 60
  end

  test "production recovers execution jobs orphaned by node loss" do
    production_config =
      Config.Reader.read!(Path.expand("../../../config/config.exs", __DIR__), env: :prod)

    oban_config = production_config[:office_graph][Oban]

    assert {Oban.Plugins.Lifeline, lifeline_options} =
             Enum.find(oban_config[:plugins], fn
               {plugin, _options} -> plugin == Oban.Plugins.Lifeline
               plugin -> plugin == Oban.Plugins.Lifeline
             end)

    assert lifeline_options[:rescue_after] == :timer.minutes(60)
  end

  test "production worker deadlines expire before orphan recovery" do
    production_config =
      Config.Reader.read!(Path.expand("../../../config/config.exs", __DIR__), env: :prod)

    oban_config = production_config[:office_graph][Oban]

    {Oban.Plugins.Lifeline, lifeline_options} =
      Enum.find(oban_config[:plugins], fn
        {plugin, _options} -> plugin == Oban.Plugins.Lifeline
        plugin -> plugin == Oban.Plugins.Lifeline
      end)

    {:ok, application_modules} = :application.get_key(:office_graph, :modules)

    worker_deadlines =
      application_modules
      |> Enum.filter(&production_oban_worker?/1)
      |> Enum.map(& &1.timeout(%Oban.Job{}))

    refute worker_deadlines == []
    assert Enum.all?(worker_deadlines, &is_integer/1)
    assert Enum.max(worker_deadlines) < lifeline_options[:rescue_after]
  end

  defp production_oban_worker?(module) do
    source =
      module.module_info(:compile)
      |> Keyword.fetch!(:source)
      |> List.to_string()
      |> Path.relative_to_cwd()

    Oban.Worker in List.wrap(module.__info__(:attributes)[:behaviour]) and
      String.starts_with?(source, "lib/")
  end
end
