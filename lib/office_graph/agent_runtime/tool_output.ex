defmodule OfficeGraph.AgentRuntime.ToolOutput do
  @moduledoc false

  @classifications [:proposal, :finding, :evidence_candidate, :message, :observation]

  @enforce_keys [:classification, :safe_summary, :structured_content]
  defstruct @enforce_keys

  @type classification :: :proposal | :finding | :evidence_candidate | :message | :observation
  @type t :: %__MODULE__{
          classification: classification(),
          safe_summary: String.t(),
          structured_content: map()
        }

  def classifications, do: @classifications

  def valid?(%__MODULE__{
        classification: classification,
        safe_summary: safe_summary,
        structured_content: content
      }) do
    classification in @classifications and safe_summary?(safe_summary) and
      structured_content?(classification, content)
  end

  def valid?(_output), do: false

  def safe_summary?(safe_summary) when is_binary(safe_summary),
    do: byte_size(safe_summary) in 1..1_000

  def safe_summary?(_safe_summary), do: false

  defp structured_content?(classification, content),
    do: is_map(content) and Map.has_key?(content, Atom.to_string(classification))
end
