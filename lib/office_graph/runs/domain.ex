defmodule OfficeGraph.Runs.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.Runs.Run, :get_work_run, :read
      list OfficeGraph.Runs.Run, :list_work_runs, :read, relay?: true
    end
  end

  json_api do
    routes do
      base_route "/work-runs", OfficeGraph.Runs.Run do
        get(:read, primary?: true)
        index :read
      end
    end
  end

  resources do
    resource OfficeGraph.Runs.Run
    resource OfficeGraph.Runs.RunRequiredCheck
    resource OfficeGraph.Runs.ExecutionObservation
    resource OfficeGraph.Runs.RunEvent
  end
end
