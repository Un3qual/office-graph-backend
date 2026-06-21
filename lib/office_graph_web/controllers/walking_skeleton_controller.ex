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

  defp render_error(conn, {:error, {:invalid_proposed_change_status, id}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "invalid_proposed_change_status",
        detail: "A proposed change is no longer pending.",
        proposed_change_id: id
      }
    })
  end

  defp render_error(conn, {:error, {:invalid_proposed_change_set, reason}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "invalid_proposed_change_set",
        detail: "The proposed change set is invalid.",
        reason: format_reason(reason)
      }
    })
  end

  defp render_error(conn, {:error, {:missing_verification_check, id}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "missing_verification_check",
        detail: "A verification check could not be found.",
        verification_check_id: id
      }
    })
  end

  defp render_error(conn, {:error, {:invalid_verification_check_status, id}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "invalid_verification_check_status",
        detail: "A verification check is no longer required.",
        verification_check_id: id
      }
    })
  end

  defp render_error(conn, {:error, {:missing_field, field}}) do
    validation_error(conn, "A required field is missing.", %{field: field})
  end

  defp render_error(conn, {:error, {:invalid_field, field}}) do
    validation_error(conn, "A field has an invalid value.", %{field: field})
  end

  defp render_error(conn, {:error, %Ash.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "validation_failed",
        detail: "Validation failed.",
        fields: Enum.map(changeset.errors, &format_changeset_error/1)
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

  defp format_changeset_error(%{field: field, message: message}) do
    %{field: field, message: message}
  end

  defp format_changeset_error(%{field: field}) do
    %{field: field, message: "is invalid"}
  end

  defp format_changeset_error(_error) do
    %{field: nil, message: "is invalid"}
  end

  defp format_reason({kind, value}), do: %{kind: kind, value: value}
  defp format_reason(reason), do: reason
end
