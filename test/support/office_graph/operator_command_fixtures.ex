defmodule OfficeGraph.OperatorCommandFixtures do
  @moduledoc false

  alias OfficeGraph.{Operations, Runs, Verification, WorkPackets}

  def create_ready_packet(session, verification_checks, attrs, operation_opts \\ []) do
    with {:ok, operation} <-
           Operations.start_operation(session, :work_packet_create, operation_opts) do
      WorkPackets.create_packet(
        session,
        operation,
        Map.merge(attrs, %{
          source_graph_item_ids: Enum.map(verification_checks, & &1.graph_item_id),
          verification_check_ids: Enum.map(verification_checks, & &1.id)
        })
      )
    end
  end

  def create_ready_run(
        session,
        verification_checks,
        packet_attrs,
        run_attrs,
        opts \\ []
      ) do
    with {:ok, packet_result} <-
           create_ready_packet(
             session,
             List.wrap(verification_checks),
             packet_attrs,
             Keyword.get(opts, :packet_operation, [])
           ),
         {:ok, operation} <-
           Operations.start_operation(
             session,
             :work_run_start,
             Keyword.get(opts, :run_operation, [])
           ),
         {:ok, run_result} <-
           Runs.start_run(session, operation, packet_result.version, run_attrs) do
      if Keyword.get(opts, :attach_packet_version?, false) do
        {:ok, Map.put(run_result, :packet_version, packet_result.version)}
      else
        {:ok, run_result}
      end
    end
  end

  def record_observation(session, run, verification_check, attrs, operation_opts \\ []) do
    with {:ok, operation} <-
           Operations.start_operation(session, :execution_observation_record, operation_opts) do
      Runs.record_observation(
        session,
        operation,
        run,
        Map.merge(attrs, %{
          verification_check_id: verification_check.id,
          graph_item_id: verification_check.graph_item_id
        })
      )
    end
  end

  def create_evidence_candidate(
        session,
        run,
        verification_check,
        observation,
        attrs,
        operation_opts \\ []
      ) do
    with {:ok, operation} <-
           Operations.start_operation(session, :evidence_candidate_create, operation_opts) do
      Verification.create_evidence_candidate(
        session,
        operation,
        Map.merge(attrs, %{
          work_run_id: run.id,
          verification_check_id: verification_check.id,
          execution_observation_id: observation.id
        })
      )
    end
  end
end
