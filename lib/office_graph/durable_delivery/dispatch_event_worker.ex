defmodule OfficeGraph.DurableDelivery.DispatchEventWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :delivery,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :queue, :args], states: :all]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id}}) do
    OfficeGraph.DurableDelivery.dispatch(event_id)
  end
end
