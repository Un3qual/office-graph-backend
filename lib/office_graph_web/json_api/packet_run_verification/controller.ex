defmodule OfficeGraphWeb.JsonApi.PacketRunVerification.Controller do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.PacketRunVerification.Serializer

  def execute(conn, params) do
    with {:ok, summary} <- ApiSupport.execute_packet_run_verification(params) do
      json(conn, Serializer.summary(summary))
    else
      error -> Errors.render(conn, error)
    end
  end
end
