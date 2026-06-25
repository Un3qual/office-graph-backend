defmodule OfficeGraphWeb.PacketRunVerificationController do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.PacketRunVerificationSerializer

  def execute(conn, params) do
    with {:ok, summary} <- ApiSupport.execute_packet_run_verification(params) do
      json(conn, PacketRunVerificationSerializer.summary(summary))
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

  defp render_error(conn, {:error, {:packet_version_not_ready, id}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "packet_version_not_ready",
        detail: "The packet version is not ready for execution.",
        packet_version_id: id
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

  defp render_error(conn, {:error, {:packet_run_flow_idempotency_conflict, flow_identity}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "idempotency_conflict",
        detail: "The packet-run-verification flow identity conflicts with different input.",
        flow_identity: flow_identity
      }
    })
  end

  defp render_error(conn, {:error, {:not_found, _resource, id}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "not_found",
        detail: "A referenced record could not be found.",
        id: id
      }
    })
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
end
