defmodule OfficeGraph.Runs.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.Runs.Run, :get_work_run, :read
      list OfficeGraph.Runs.Run, :list_work_runs, :read, relay?: true

      get OfficeGraph.Runs.RunRequiredCheck, :get_run_required_check, :read

      list OfficeGraph.Runs.RunRequiredCheck, :list_run_required_checks, :read, relay?: true

      get OfficeGraph.Runs.ExecutionObservation, :get_execution_observation, :read

      list OfficeGraph.Runs.ExecutionObservation, :list_execution_observations, :read,
        relay?: true
    end
  end

  json_api do
    routes do
      base_route "/work-runs", OfficeGraph.Runs.Run do
        get(:read, primary?: true)
        index :read
      end

      base_route "/run-required-checks", OfficeGraph.Runs.RunRequiredCheck do
        get(:read, primary?: true)
        index :read
      end

      base_route "/execution-observations", OfficeGraph.Runs.ExecutionObservation do
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
