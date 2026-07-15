defmodule OfficeGraph.GitHubIntegration.Adapter.Unavailable do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.Adapter

  @impl true
  def fetch(_request), do: {:error, :adapter_unavailable}

  @impl true
  def find_review_reply(_request, _credential), do: {:error, :adapter_unavailable}

  @impl true
  def reply_to_review(_request, _credential), do: {:error, :adapter_unavailable}

  @impl true
  def update_check(_request, _credential), do: {:error, :adapter_unavailable}
end
