defmodule OfficeGraphWeb.JsonApi.OperatorWorkflow.Controller do
  use OfficeGraphWeb, :controller

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.JsonApi.Common.Errors
  alias OfficeGraphWeb.JsonApi.OperatorWorkflow.Serializer

  @not_found_opts [not_found_status: :not_found]

  def inbox(conn, params) do
    params = request_context_params(conn, params)

    with {:ok, inbox} <- ApiSupport.read_operator_inbox(params) do
      json(conn, Serializer.inbox(inbox))
    else
      error -> Errors.render(conn, error, @not_found_opts)
    end
  end

  def item(conn, %{"id" => id} = params) do
    params = Map.put(params, "normalized_event_id", id)
    params = request_context_params(conn, params)

    with {:ok, item} <- ApiSupport.read_operator_workflow_item(params) do
      json(conn, Serializer.item(item))
    else
      error -> Errors.render(conn, error, @not_found_opts)
    end
  end

  def packet_readiness(conn, params) do
    params = request_context_params(conn, params)

    with {:ok, readiness} <- ApiSupport.read_operator_packet_readiness(params) do
      json(conn, Serializer.packet_readiness(readiness))
    else
      error -> Errors.render(conn, error, @not_found_opts)
    end
  end

  def run_state(conn, %{"id" => id} = params) do
    params = Map.put(params, "run_id", id)
    params = request_context_params(conn, params)

    with {:ok, run_state} <- ApiSupport.read_operator_run_state(params) do
      json(conn, Serializer.run_state(run_state))
    else
      error -> Errors.render(conn, error, @not_found_opts)
    end
  end

  def verification_outcome(conn, %{"id" => id} = params) do
    params = Map.put(params, "run_id", id)
    params = request_context_params(conn, params)

    with {:ok, outcome} <- ApiSupport.read_operator_verification_outcome(params) do
      json(conn, Serializer.verification_outcome(outcome))
    else
      error -> Errors.render(conn, error, @not_found_opts)
    end
  end

  defp request_context_params(conn, params) do
    ApiSupport.with_request_session_context(params, Ash.PlugHelpers.get_actor(conn))
  end
end
