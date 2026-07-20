defmodule OfficeGraph.AgentRuntime.AdapterRegistry do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{ModelAdapter, ToolAdapter}

  @type adapter_kind :: :model | :tool
  @type configuration :: %{models: %{String.t() => module()}, tools: %{String.t() => module()}}

  def model(key), do: resolve(:model, key)
  def tool(key), do: resolve(:tool, key)

  def validate(configuration \\ configured()) do
    configuration = Map.new(configuration)

    with :ok <- validate_adapters(:model, configuration.models),
         :ok <- validate_adapters(:tool, configuration.tools) do
      :ok
    end
  end

  defp resolve(kind, key) when is_binary(key) do
    adapters = configured() |> Map.new() |> Map.fetch!(plural(kind))

    case Map.fetch(adapters, key) do
      {:ok, adapter} ->
        case validate_adapter(kind, key, adapter) do
          :ok -> {:ok, adapter}
          {:error, reason} -> {:error, reason}
        end

      :error ->
        {:error, :adapter_not_found}
    end
  end

  defp resolve(_kind, _key), do: {:error, :adapter_not_found}

  defp validate_adapters(kind, adapters) when is_map(adapters) do
    Enum.reduce_while(adapters, :ok, fn {key, adapter}, :ok ->
      case validate_adapter(kind, key, adapter) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {kind, reason}}}
      end
    end)
  end

  defp validate_adapters(kind, _adapters), do: {:error, {kind, :invalid_registry_configuration}}

  defp validate_adapter(:model, key, adapter), do: validate_adapter(key, adapter, ModelAdapter)
  defp validate_adapter(:tool, key, adapter), do: validate_adapter(key, adapter, ToolAdapter)

  defp validate_adapter(key, adapter, behaviour) when is_atom(adapter) do
    with true <- Code.ensure_loaded?(adapter),
         true <- behaviour in (adapter.module_info(:attributes)[:behaviour] || []),
         true <- function_exported?(adapter, :manifest, 0),
         %{key: ^key} <- adapter.manifest() do
      :ok
    else
      false -> {:error, :invalid_adapter_module}
      _other -> {:error, :manifest_key_mismatch}
    end
  end

  defp validate_adapter(_key, _adapter, _behaviour), do: {:error, :invalid_adapter_module}

  defp configured do
    Application.get_env(:office_graph, :agent_runtime_adapters, %{models: %{}, tools: %{}})
  end

  defp plural(:model), do: :models
  defp plural(:tool), do: :tools
end
