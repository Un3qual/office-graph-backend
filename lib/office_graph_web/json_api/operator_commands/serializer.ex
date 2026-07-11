defmodule OfficeGraphWeb.JsonApi.OperatorCommands.Serializer do
  @moduledoc false

  import Phoenix.Controller, only: [json: 2]

  def render(conn, command, operation_id, affected_ids, result) do
    json(conn, %{
      command: command,
      operation_id: operation_id,
      affected_ids: affected_ids,
      result: result
    })
  end
end
