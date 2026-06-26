defmodule OfficeGraph.Runs.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  resources do
    resource OfficeGraph.Runs.Run
    resource OfficeGraph.Runs.RunRequiredCheck
    resource OfficeGraph.Runs.ExecutionObservation
    resource OfficeGraph.Runs.RunEvent
  end
end
