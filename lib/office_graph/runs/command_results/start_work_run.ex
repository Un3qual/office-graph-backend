defmodule OfficeGraph.Runs.CommandResults.StartWorkRun do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :run, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Runs.Run]

    field :required_checks, {:array, :struct},
      allow_nil?: false,
      constraints: [items: [instance_of: OfficeGraph.Runs.RunRequiredCheck]]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :start_work_run_payload

  def from_result(operation, result) do
    new(
      command: "start_work_run",
      operation_id: operation.id,
      affected_ids:
        [TypedId.new!(type: "work_run", id: result.run.id)] ++
          Enum.map(
            result.required_checks,
            &TypedId.new!(type: "run_required_check", id: &1.id)
          ),
      run: result.run,
      required_checks: result.required_checks
    )
  end
end

defimpl Jason.Encoder, for: OfficeGraph.Runs.CommandResults.StartWorkRun do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        run: run_result(result.run),
        required_checks: Enum.map(result.required_checks, &required_check_result/1)
      },
      options
    )
  end

  defp run_result(run) do
    %{
      id: run.id,
      work_packet_version_id: run.work_packet_version_id,
      execution_state: run.execution_state,
      verification_state: run.verification_state,
      aggregate_state: run.aggregate_state
    }
  end

  defp required_check_result(required_check) do
    %{
      id: required_check.id,
      verification_check_id: required_check.verification_check_id,
      state: required_check.state
    }
  end
end
