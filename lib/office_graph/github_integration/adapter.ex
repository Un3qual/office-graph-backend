defmodule OfficeGraph.GitHubIntegration.Adapter do
  @moduledoc """
  Provider boundary used by reconciliation and the two explicitly supported outbound actions.
  """

  @callback fetch(request :: struct()) :: {:ok, struct()} | {:error, term()}
  @callback reply_to_review(request :: map(), credential :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback update_check(request :: map(), credential :: String.t()) ::
              {:ok, map()} | {:error, term()}
end
