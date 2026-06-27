defmodule OfficeGraphWeb.JsonApi.Router do
  @moduledoc false

  use AshJsonApi.Router,
    domains: [
      OfficeGraph.WorkGraph.Domain,
      OfficeGraph.WorkPackets.Domain,
      OfficeGraph.Runs.Domain
    ],
    prefix: "/api/v1"
end
