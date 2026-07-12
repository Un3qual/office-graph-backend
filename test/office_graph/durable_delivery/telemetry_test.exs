defmodule OfficeGraph.DurableDelivery.TelemetryTest do
  use ExUnit.Case, async: true

  test "Oban lifecycle metrics expose operational tags without job arguments or tenant scope" do
    metrics = OfficeGraphWeb.Telemetry.metrics()

    for event_name <- [[:oban, :job, :stop], [:oban, :job, :exception]] do
      metric = Enum.find(metrics, &(&1.event_name == event_name))
      assert metric
      assert is_function(metric.measurement, 1)
      assert Enum.sort(metric.tags) == [:attempt, :queue, :state, :worker]

      tags =
        metric.tag_values.(%{
          job: %Oban.Job{
            worker: "Worker",
            queue: "delivery",
            attempt: 2,
            args: %{"secret" => true}
          },
          state: :failure,
          organization_id: Ecto.UUID.generate()
        })

      assert tags == %{worker: "Worker", queue: "delivery", attempt: 2, state: :failure}
      refute Map.has_key?(tags, :args)
      refute Map.has_key?(tags, :organization_id)
    end
  end
end
