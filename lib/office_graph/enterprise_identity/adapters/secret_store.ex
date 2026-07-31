defmodule OfficeGraph.EnterpriseIdentity.SecretStore do
  @moduledoc """
  Resolves WorkOS secret references without exposing secret values to product resources.
  """

  @callback resolve(reference :: String.t()) ::
              {:ok, String.t()} | {:error, :invalid_secret_reference | :secret_not_found}

  def resolve(reference) when is_binary(reference) do
    implementation().resolve(reference)
  end

  def resolve(_reference), do: {:error, :invalid_secret_reference}

  defp implementation do
    Application.fetch_env!(:office_graph, :workos_secret_store)
  end
end

defmodule OfficeGraph.EnterpriseIdentity.SecretStore.Environment do
  @moduledoc false

  @behaviour OfficeGraph.EnterpriseIdentity.SecretStore

  @environment_reference ~r/\Aenv:([A-Z][A-Z0-9_]*)\z/

  @impl true
  def resolve(reference) when is_binary(reference) do
    case Regex.run(@environment_reference, reference, capture: :all_but_first) do
      [variable] ->
        case System.get_env(variable) do
          value when is_binary(value) and value != "" -> {:ok, value}
          _missing -> {:error, :secret_not_found}
        end

      _invalid ->
        {:error, :invalid_secret_reference}
    end
  end

  def resolve(_reference), do: {:error, :invalid_secret_reference}
end
