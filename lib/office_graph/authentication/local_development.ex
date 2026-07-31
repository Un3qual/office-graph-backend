defmodule OfficeGraph.Authentication.LocalDevelopment do
  @moduledoc false

  def enabled? do
    :office_graph
    |> Application.get_env(:local_development_authentication, [])
    |> Keyword.get(:enabled, false)
    |> Kernel.==(true)
  end
end
