defmodule OfficeGraph.Runs.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      list OfficeGraph.Runs.Run, :list_work_runs, :read, paginate_with: nil
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
