defmodule OfficeGraph.AgentRuntime.RoutedOutputBatch do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{ModelOutput, ToolOutput}

  @max_summary_bytes 1_000

  @output_specs [
    %{
      classification: :message,
      content_field: "body",
      content_value: "review_complete",
      suffix: "completed against authorized context"
    },
    %{
      classification: :finding,
      content_field: "summary",
      content_value: "bounded_follow_up",
      suffix: "found a bounded follow-up"
    },
    %{
      classification: :proposal,
      content_field: "intent",
      content_value: "follow_up",
      suffix: "proposed a bounded task"
    },
    %{
      classification: :observation,
      content_field: "subject",
      content_value: "review_check",
      suffix: "recorded a non-authoritative check"
    },
    %{
      classification: :evidence_candidate,
      content_field: "check",
      content_value: "openspec_review",
      suffix: "produced candidate verification material"
    }
  ]

  @enforce_keys [:outputs]
  defstruct @enforce_keys

  @type t :: %__MODULE__{outputs: [ModelOutput.t()]}

  def content_schema do
    fields =
      Map.new(@output_specs, fn spec ->
        {classification_key(spec),
         {:map,
          %{
            required: ["safe_summary", spec.content_field],
            fields: %{
              "safe_summary" => {:string, @max_summary_bytes},
              spec.content_field => {:string, @max_summary_bytes}
            },
            max_serialized_bytes: 1_200
          }}}
      end)

    %{
      required: Enum.map(@output_specs, &classification_key/1),
      fields: fields,
      max_serialized_bytes: 8_192
    }
  end

  def build(review_summary) when is_binary(review_summary) do
    routed_outputs =
      Map.new(@output_specs, fn spec ->
        {classification_key(spec),
         %{
           "safe_summary" => bounded_summary(review_summary, spec.suffix),
           spec.content_field => spec.content_value
         }}
      end)

    %ToolOutput{
      classification: :observation,
      safe_summary: review_summary,
      structured_content: %{"observation" => routed_outputs}
    }
  end

  def from_tool_output(%ToolOutput{
        classification: :observation,
        structured_content: %{"observation" => routed_outputs}
      })
      when is_map(routed_outputs) do
    outputs =
      Enum.map(@output_specs, fn spec ->
        routed_output = Map.fetch!(routed_outputs, classification_key(spec))

        %ModelOutput{
          classification: spec.classification,
          safe_summary: Map.fetch!(routed_output, "safe_summary"),
          structured_content: %{
            classification_key(spec) => %{
              spec.content_field => Map.fetch!(routed_output, spec.content_field)
            }
          }
        }
      end)

    if Enum.all?(outputs, &ModelOutput.valid?/1),
      do: {:ok, %__MODULE__{outputs: outputs}},
      else: {:error, :malformed_routed_output_batch}
  rescue
    _error in [KeyError, BadMapError] -> {:error, :malformed_routed_output_batch}
  end

  def from_tool_output(_output), do: {:error, :malformed_routed_output_batch}

  defp bounded_summary(review_summary, suffix) do
    suffix = " " <> suffix
    prefix = truncate_utf8(review_summary, @max_summary_bytes - byte_size(suffix))
    prefix <> suffix
  end

  defp truncate_utf8(value, max_bytes) when byte_size(value) <= max_bytes, do: value

  defp truncate_utf8(value, max_bytes) do
    value
    |> String.graphemes()
    |> Enum.reduce_while("", fn grapheme, bounded ->
      if byte_size(bounded) + byte_size(grapheme) <= max_bytes,
        do: {:cont, bounded <> grapheme},
        else: {:halt, bounded}
    end)
  end

  defp classification_key(%{classification: classification}), do: Atom.to_string(classification)
end
