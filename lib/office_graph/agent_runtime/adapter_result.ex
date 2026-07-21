defmodule OfficeGraph.AgentRuntime.AdapterResult do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{ModelOutput, ToolOutput}

  @type classification :: :retryable | :terminal | :cancelled
  @type failure :: {classification(), atom()}
  @type t :: {:ok, ModelOutput.t() | ToolOutput.t()} | {:error, failure()}

  def normalize({:ok, %ModelOutput{} = output}) do
    if ModelOutput.valid?(output), do: {:ok, output}, else: invalid_result()
  end

  def normalize({:ok, %ToolOutput{} = output}) do
    if ToolOutput.valid?(output), do: {:ok, output}, else: invalid_result()
  end

  def normalize({:error, {classification, code}})
      when classification in [:retryable, :terminal, :cancelled] and is_atom(code) and
             not is_nil(code),
      do: {:error, {classification, code}}

  def normalize(_result), do: invalid_result()

  defp invalid_result, do: {:error, {:terminal, :invalid_adapter_result}}
end
