defmodule OfficeGraph.ApiSupport do
  @moduledoc """
  Local API owner bootstrap support.
  """

  use Boundary,
    deps: [OfficeGraph.Foundation],
    exports: []

  alias OfficeGraph.Foundation

  def bootstrap_local_api_owner do
    if Application.get_env(:office_graph, :allow_local_api_owner_bootstrap, false) do
      Foundation.bootstrap_local_owner([])
    else
      {:error, :forbidden}
    end
  end
end
