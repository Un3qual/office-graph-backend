defmodule OfficeGraphWeb.JsonApi.Compatibility.Controller do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.Compatibility.Serializer

  def manual_intake(conn, params) do
    with {:ok, intake} <- ApiSupport.submit_manual_intake(params) do
      json(conn, Serializer.intake(intake))
    else
      error -> Errors.render(conn, error)
    end
  end

  def apply_proposed_changes(conn, params) do
    with {:ok, applied} <- ApiSupport.apply_proposed_changes(params) do
      json(conn, Serializer.applied(applied))
    else
      error -> Errors.render(conn, error)
    end
  end

  def complete_verification(conn, params) do
    with {:ok, completed} <- ApiSupport.complete_verification(params) do
      json(conn, Serializer.completed(completed))
    else
      error -> Errors.render(conn, error)
    end
  end
end
