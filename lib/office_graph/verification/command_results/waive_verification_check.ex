defmodule OfficeGraph.Verification.CommandResults.WaiveVerificationCheck do
  @moduledoc false

  alias OfficeGraph.CommandSupport.TypedId

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, TypedId}, allow_nil?: false

    field :verification_result, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.WorkGraph.VerificationResult]

    field :required_check, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Runs.RunRequiredCheck]

    field :run, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Runs.Run]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :waive_verification_check_payload

  def from_result(operation, result) do
    new(
      command: "waive_verification_check",
      operation_id: operation.id,
      affected_ids: [
        TypedId.new!(type: "verification_result", id: result.verification_result.id),
        TypedId.new!(type: "run_required_check", id: result.required_check.id),
        TypedId.new!(type: "work_run", id: result.run.id)
      ],
      verification_result: result.verification_result,
      required_check: result.required_check,
      run: result.run
    )
  end
end

defimpl Jason.Encoder,
  for: OfficeGraph.Verification.CommandResults.WaiveVerificationCheck do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        verification_result: %{
          id: result.verification_result.id,
          result: result.verification_result.result
        },
        required_check: %{
          id: result.required_check.id,
          verification_check_id: result.required_check.verification_check_id,
          state: result.required_check.state
        },
        run: %{
          id: result.run.id,
          work_packet_version_id: result.run.work_packet_version_id,
          execution_state: result.run.execution_state,
          verification_state: result.run.verification_state,
          aggregate_state: result.run.aggregate_state
        }
      },
      options
    )
  end
end
