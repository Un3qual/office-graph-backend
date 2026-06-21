defmodule OfficeGraphWeb.WalkingSkeletonController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.WalkingSkeletonSerializer

  def manual_intake(conn, params) do
    with {:ok, intake} <- ApiSupport.submit_manual_intake(params) do
      json(conn, WalkingSkeletonSerializer.intake(intake))
    else
      error -> render_error(conn, error)
    end
  end

  def apply_proposed_changes(conn, params) do
    with {:ok, applied} <- ApiSupport.apply_proposed_changes(params) do
      json(conn, WalkingSkeletonSerializer.applied(applied))
    else
      error -> render_error(conn, error)
    end
  end

  def complete_verification(conn, params) do
    with {:ok, completed} <- ApiSupport.complete_verification(params) do
      json(conn, WalkingSkeletonSerializer.completed(completed))
    else
      error -> render_error(conn, error)
    end
  end

  defp render_error(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: %{code: "forbidden", detail: "The action is not authorized."}})
  end

  defp render_error(conn, {:error, {:invalid_proposed_change, id}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "invalid_proposed_change",
        detail: "A proposed change failed validation.",
        proposed_change_id: id
      }
    })
  end

  defp render_error(conn, {:error, {:missing_proposed_change, id}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "missing_proposed_change",
        detail: "A proposed change could not be found.",
        proposed_change_id: id
      }
    })
  end

  defp render_error(conn, {:error, changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_failed", detail: inspect(changeset.errors)}})
  end
end
