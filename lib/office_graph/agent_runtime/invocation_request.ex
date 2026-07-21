defmodule OfficeGraph.AgentRuntime.InvocationRequest do
  @moduledoc """
  Typed, bounded input for a run-linked agent invocation.

  The request deliberately excludes raw prompts and caller-selected tools. Those
  values come from the approved definition and authorized context package.
  """

  @enforce_keys [
    :binding_id,
    :graph_item_id,
    :run_id,
    :origin,
    :invocation_mode,
    :idempotency_key,
    :requested_outcome,
    :requested_capabilities,
    :autonomy_mode
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          binding_id: Ecto.UUID.t(),
          graph_item_id: Ecto.UUID.t(),
          run_id: Ecto.UUID.t(),
          origin: String.t(),
          invocation_mode: String.t(),
          idempotency_key: String.t(),
          requested_outcome: String.t(),
          requested_capabilities: [String.t()],
          autonomy_mode: String.t()
        }

  @fields @enforce_keys
  @origins ~w(operator system_trigger)
  @invocation_modes ~w(human automatic)
  @autonomy_modes ~w(human_supervised bounded_automatic)
  @capability_pattern ~r/\A[a-z][a-z0-9_.-]*\z/

  def new(attrs) when is_map(attrs) and not is_struct(attrs) do
    with :ok <- reject_unknown_fields(attrs),
         {:ok, binding_id} <- required_uuid(attrs, :binding_id),
         {:ok, graph_item_id} <- required_uuid(attrs, :graph_item_id),
         {:ok, run_id} <- required_uuid(attrs, :run_id),
         {:ok, origin} <- required_enum(attrs, :origin, @origins),
         {:ok, invocation_mode} <-
           required_enum(attrs, :invocation_mode, @invocation_modes),
         {:ok, idempotency_key} <- required_string(attrs, :idempotency_key, 255),
         {:ok, requested_outcome} <- required_string(attrs, :requested_outcome, 2_000),
         {:ok, requested_capabilities} <- required_capabilities(attrs),
         {:ok, autonomy_mode} <- required_enum(attrs, :autonomy_mode, @autonomy_modes) do
      {:ok,
       %__MODULE__{
         binding_id: binding_id,
         graph_item_id: graph_item_id,
         run_id: run_id,
         origin: origin,
         invocation_mode: invocation_mode,
         idempotency_key: idempotency_key,
         requested_outcome: requested_outcome,
         requested_capabilities: requested_capabilities,
         autonomy_mode: autonomy_mode
       }}
    end
  end

  def new(_attrs), do: {:error, :invalid_invocation_request}

  def new!(attrs) do
    case new(attrs) do
      {:ok, request} -> request
      {:error, reason} -> raise ArgumentError, "invalid invocation request: #{inspect(reason)}"
    end
  end

  def command_input(%__MODULE__{} = request) do
    request
    |> Map.from_struct()
    |> Map.update!(:requested_capabilities, &Enum.sort/1)
  end

  defp reject_unknown_fields(attrs) do
    allowed = MapSet.new(@fields ++ Enum.map(@fields, &Atom.to_string/1))

    case Enum.find(Map.keys(attrs), &(not MapSet.member?(allowed, &1))) do
      nil -> :ok
      field -> {:error, {:invalid_field, field}}
    end
  end

  defp required_uuid(attrs, field) do
    case fetch(attrs, field) do
      {:ok, value} ->
        case Ecto.UUID.cast(value) do
          {:ok, uuid} -> {:ok, uuid}
          :error -> {:error, {:invalid_field, field}}
        end

      :error ->
        {:error, {:missing_field, field}}
    end
  end

  defp required_string(attrs, field, max_bytes) do
    case fetch(attrs, field) do
      {:ok, value} when is_binary(value) ->
        normalized = String.trim(value)

        if normalized != "" and byte_size(normalized) <= max_bytes,
          do: {:ok, normalized},
          else: {:error, {:invalid_field, field}}

      {:ok, _value} ->
        {:error, {:invalid_field, field}}

      :error ->
        {:error, {:missing_field, field}}
    end
  end

  defp required_enum(attrs, field, allowed) do
    with {:ok, value} <- required_string(attrs, field, 255),
         true <- value in allowed do
      {:ok, value}
    else
      false -> {:error, {:invalid_field, field}}
      {:error, _reason} = error -> error
    end
  end

  defp required_capabilities(attrs) do
    case fetch(attrs, :requested_capabilities) do
      {:ok, capabilities} when is_list(capabilities) and capabilities != [] ->
        normalized = Enum.map(capabilities, &normalize_capability/1)

        cond do
          Enum.any?(normalized, &match?(:error, &1)) ->
            {:error, {:invalid_field, :requested_capabilities}}

          length(normalized) != length(Enum.uniq(normalized)) ->
            {:error, {:invalid_field, :requested_capabilities}}

          true ->
            {:ok, Enum.sort(normalized)}
        end

      {:ok, _capabilities} ->
        {:error, {:invalid_field, :requested_capabilities}}

      :error ->
        {:error, {:missing_field, :requested_capabilities}}
    end
  end

  defp normalize_capability(value) when is_binary(value) do
    normalized = String.trim(value)

    if byte_size(normalized) in 1..255 and Regex.match?(@capability_pattern, normalized),
      do: normalized,
      else: :error
  end

  defp normalize_capability(_value), do: :error

  defp fetch(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(attrs, Atom.to_string(field))
    end
  end
end
