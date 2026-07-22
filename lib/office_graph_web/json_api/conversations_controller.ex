defmodule OfficeGraphWeb.JsonApi.ConversationsController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.NodeConversations
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.RequestSession

  def show(conn, %{"run_id" => run_id, "graph_item_id" => graph_item_id}) do
    with {:ok, session_context} <- request_session(conn),
         {:ok, projection} <-
           NodeConversations.project(session_context, run_id, graph_item_id) do
      json(conn, %{data: projection})
    else
      error -> Errors.render(conn, error)
    end
  end

  defp request_session(conn) do
    conn
    |> Ash.PlugHelpers.get_actor()
    |> RequestSession.resolve()
  end
end
