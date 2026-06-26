defmodule OfficeGraphWeb.OperatorWorkflowController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.OperatorWorkflowSerializer

  def inbox(conn, params) do
    with {:ok, inbox} <- ApiSupport.read_operator_inbox(params) do
      json(conn, OperatorWorkflowSerializer.inbox(inbox))
    else
      error -> render_error(conn, error)
    end
  end

  def item(conn, %{"id" => id} = params) do
    params = Map.put(params, "normalized_event_id", id)

    with {:ok, item} <- ApiSupport.read_operator_workflow_item(params) do
      json(conn, OperatorWorkflowSerializer.item(item))
    else
      error -> render_error(conn, error)
    end
  end

  def packet_readiness(conn, params) do
    with {:ok, readiness} <- ApiSupport.read_operator_packet_readiness(params) do
      json(conn, OperatorWorkflowSerializer.packet_readiness(readiness))
    else
      error -> render_error(conn, error)
    end
  end

  def run_state(conn, %{"id" => id} = params) do
    params = Map.put(params, "run_id", id)

    with {:ok, run_state} <- ApiSupport.read_operator_run_state(params) do
      json(conn, OperatorWorkflowSerializer.run_state(run_state))
    else
      error -> render_error(conn, error)
    end
  end

  def verification_outcome(conn, %{"id" => id} = params) do
    params = Map.put(params, "run_id", id)

    with {:ok, outcome} <- ApiSupport.read_operator_verification_outcome(params) do
      json(conn, OperatorWorkflowSerializer.verification_outcome(outcome))
    else
      error -> render_error(conn, error)
    end
  end

  defp render_error(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: %{code: "forbidden", detail: "The action is not authorized."}})
  end

  defp render_error(conn, {:error, {:missing_field, field}}) do
    validation_error(conn, "A required field is missing.", %{field: field})
  end

  defp render_error(conn, {:error, {:invalid_field, field}}) do
    validation_error(conn, "A field has an invalid value.", %{field: field})
  end

  defp render_error(conn, {:error, {:missing_normalized_intake_event, id}}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: %{
        code: "not_found",
        detail: "The operator workflow item could not be found.",
        normalized_event_id: id
      }
    })
  end

  defp render_error(conn, {:error, {:not_found, _resource, id}}) do
    conn
    |> put_status(:not_found)
    |> json(%{
      error: %{
        code: "not_found",
        detail: "A referenced record could not be found.",
        id: id
      }
    })
  end

  defp render_error(conn, {:error, _error}) do
    validation_error(conn, "Validation failed.")
  end

  defp validation_error(conn, detail, extra \\ %{}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: Map.merge(%{code: "validation_failed", detail: detail}, extra)})
  end
end
