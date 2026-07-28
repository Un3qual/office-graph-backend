defmodule OfficeGraph.GitHubIntegration.SecretStore.TestAdapter do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.SecretStore

  @table __MODULE__

  def put(secrets) when is_map(secrets) do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ets.insert(@table, Enum.to_list(secrets))
    :ok
  end

  @impl true
  def fetch(reference, _scope) when is_binary(reference) do
    ensure_table!()

    case :ets.lookup(@table, reference) do
      [{^reference, secret}] when is_binary(secret) -> {:ok, secret}
      [] -> {:error, :secret_not_found}
    end
  end

  def fetch(_reference, _scope), do: {:error, :invalid_secret_reference}

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError -> @table
        end

      table ->
        table
    end
  end
end
