defmodule OfficeGraphWeb.JsonApi.GitHubHealthController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.Projections
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.RequestSession

  def show(conn, %{"installation_id" => installation_id} = params) do
    with {:ok, session_context} <- request_session(conn),
         {:ok, health} <-
           Projections.integration_health(session_context, installation_id,
             limit: normalize_limit(Map.get(params, "limit"))
           ) do
      json(conn, %{data: health})
    else
      error -> Errors.render(conn, error)
    end
  end

  defp request_session(conn) do
    conn
    |> Ash.PlugHelpers.get_actor()
    |> RequestSession.resolve()
  end

  defp normalize_limit(nil), do: 20

  defp normalize_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} -> limit
      _invalid -> 20
    end
  end

  defp normalize_limit(value), do: value
end
