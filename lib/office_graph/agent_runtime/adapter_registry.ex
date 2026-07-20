defmodule OfficeGraph.AgentRuntime.AdapterRegistry do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{AdapterContract, ModelAdapter, ToolAdapter}

  @type adapter_kind :: :model | :tool
  @type configuration :: %{
          required(:models) => %{String.t() => module()},
          required(:tools) => %{String.t() => module()}
        }

  def model(key), do: resolve(:model, key)
  def tool(key), do: resolve(:tool, key)

  def validate(configuration \\ configured()) do
    with {:ok, configuration} <- normalize_configuration(configuration),
         :ok <- validate_adapters(:model, configuration.models),
         :ok <- validate_adapters(:tool, configuration.tools) do
      :ok
    end
  end

  defp resolve(kind, key) when is_binary(key) do
    with {:ok, configuration} <- normalize_configuration(configured()),
         adapters <- Map.fetch!(configuration, plural(kind)),
         {:ok, adapter} <- Map.fetch(adapters, key),
         :ok <- validate_adapter(kind, key, adapter) do
      {:ok, adapter}
    else
      :error -> {:error, :adapter_not_found}
      {:error, _reason} = error -> error
    end
  end

  defp resolve(_kind, _key), do: {:error, :adapter_not_found}

  defp normalize_configuration(configuration) when is_list(configuration) do
    if Enum.all?(configuration, &match?({_, _}, &1)) do
      normalize_configuration(Map.new(configuration))
    else
      {:error, {:registry, :invalid_configuration}}
    end
  end

  defp normalize_configuration(%{models: models, tools: tools})
       when is_map(models) and is_map(tools) do
    {:ok, %{models: models, tools: tools}}
  end

  defp normalize_configuration(_configuration), do: {:error, {:registry, :invalid_configuration}}

  defp validate_adapters(kind, adapters) do
    Enum.reduce_while(adapters, :ok, fn {key, adapter}, :ok ->
      case validate_adapter(kind, key, adapter) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {kind, reason}}}
      end
    end)
  end

  defp validate_adapter(:model, key, adapter) do
    validate_adapter(key, adapter, ModelAdapter, &AdapterContract.valid_model_manifest?/1)
  end

  defp validate_adapter(:tool, key, adapter) do
    validate_adapter(key, adapter, ToolAdapter, &AdapterContract.valid_tool_manifest?/1)
  end

  defp validate_adapter(key, adapter, behaviour, valid_manifest?)
       when is_binary(key) and is_atom(adapter) do
    with true <- Code.ensure_loaded?(adapter),
         true <- declares_behaviour?(adapter, behaviour),
         true <- required_callbacks?(adapter) do
      safe_manifest(adapter, key, valid_manifest?)
    else
      false -> {:error, :invalid_adapter_module}
    end
  end

  defp validate_adapter(_key, _adapter, _behaviour, _valid_manifest?),
    do: {:error, :invalid_adapter_module}

  defp validate_manifest_key(key, manifest, valid_manifest?) when is_struct(manifest) do
    cond do
      not valid_manifest?.(manifest) -> {:error, :invalid_manifest}
      manifest.key != key -> {:error, :manifest_key_mismatch}
      true -> :ok
    end
  end

  defp validate_manifest_key(_key, _manifest, _valid_manifest?), do: {:error, :invalid_manifest}

  defp required_callbacks?(adapter) do
    Enum.all?([{:manifest, 0}, {:invoke, 1}, {:cancel, 1}], fn {function, arity} ->
      function_exported?(adapter, function, arity)
    end)
  end

  defp declares_behaviour?(adapter, behaviour) do
    behaviours =
      adapter.module_info(:attributes)
      |> Keyword.get_values(:behaviour)
      |> List.flatten()

    behaviour in behaviours
  end

  defp safe_manifest(adapter, key, valid_manifest?) do
    validate_manifest_key(key, adapter.manifest(), valid_manifest?)
  catch
    :error, _reason -> {:error, :invalid_manifest}
    :exit, _reason -> {:error, :invalid_manifest}
    :throw, _reason -> {:error, :invalid_manifest}
  end

  defp configured, do: Application.get_env(:office_graph, :agent_runtime_adapters, %{})
  defp plural(:model), do: :models
  defp plural(:tool), do: :tools
end
