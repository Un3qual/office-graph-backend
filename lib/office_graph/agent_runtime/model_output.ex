defmodule OfficeGraph.AgentRuntime.ModelOutput do
  @moduledoc false

  @classifications [:proposal, :finding, :evidence_candidate, :message, :observation]

  @enforce_keys [:classification, :safe_summary]
  defstruct @enforce_keys

  @type classification :: :proposal | :finding | :evidence_candidate | :message | :observation
  @type t :: %__MODULE__{classification: classification(), safe_summary: String.t()}

  def classifications, do: @classifications

  def valid?(%__MODULE__{classification: classification, safe_summary: safe_summary}) do
    classification in @classifications and safe_summary?(safe_summary)
  end

  def valid?(_output), do: false

  def safe_summary?(safe_summary) when is_binary(safe_summary),
    do: byte_size(safe_summary) in 1..1_000

  def safe_summary?(_safe_summary), do: false
end
