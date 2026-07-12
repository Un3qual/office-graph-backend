defmodule OfficeGraph.DurableDelivery.TerminalJob do
  @moduledoc """
  Safe operator-facing summary of terminal durable work.
  """

  @enforce_keys [:id, :worker, :queue, :state, :attempt, :max_attempts]
  defstruct @enforce_keys ++
              [:failure_code, :attempted_at, :cancelled_at, :discarded_at]
end
