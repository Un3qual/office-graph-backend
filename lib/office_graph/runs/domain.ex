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

    mutations do
      action OfficeGraph.Runs.Run, :start_work_run, :start_work_run do
        relay_id_translations(input: [packet_version_id: :work_packet_version])
      end

      action OfficeGraph.Runs.Run,
             :record_execution_observation,
             :record_execution_observation do
        relay_id_translations(
          input: [
            run_id: :work_run,
            verification_check_id: :verification_check,
            source_graph_item_id: :graph_item
          ]
        )
      end
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

      route(
        OfficeGraph.Runs.Run,
        :post,
        "/commands/start-work-run",
        :start_work_run
      )

      route(
        OfficeGraph.Runs.Run,
        :post,
        "/commands/record-execution-observation",
        :record_execution_observation
      )
    end
  end

  resources do
    resource OfficeGraph.Runs.Run
    resource OfficeGraph.Runs.RunRequiredCheck
    resource OfficeGraph.Runs.ExecutionObservation
    resource OfficeGraph.Runs.RunEvent
  end
end
