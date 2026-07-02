defmodule OfficeGraphWeb.GraphQL.OperatorWorkflow.Queries do
  use Absinthe.Schema.Notation

  alias OfficeGraph.Projections
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.RequestSession

  object :operator_workflow_queries do
    field :operator_inbox, non_null(:operator_inbox) do
      resolve(fn _, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, inbox} <- Projections.operator_inbox(session_context) do
          {:ok, inbox}
        else
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_workflow_item, non_null(:operator_workflow_item) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, item} <- Projections.operator_workflow_item(session_context, id) do
          {:ok, item}
        else
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_packet_readiness, non_null(:operator_packet_readiness) do
      arg(:input, non_null(:operator_packet_readiness_input))

      resolve(fn %{input: input}, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, readiness} <-
               Projections.packet_readiness(
                 session_context,
                 normalize_packet_readiness_input(input)
               ) do
          {:ok, readiness}
        else
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_run_state, non_null(:operator_run_state) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, run_state} <- Projections.operator_run_state(session_context, id) do
          {:ok, run_state}
        else
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_verification_outcome, non_null(:operator_verification_outcome) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, outcome} <- Projections.verification_outcome(session_context, id) do
          {:ok, outcome}
        else
          error -> Errors.to_absinthe(error)
        end
      end)
    end
  end

  defp normalize_packet_readiness_input(input) do
    input
    |> Map.update(:source_graph_item_ids, [], &normalize_list/1)
    |> Map.update(:verification_check_ids, [], &normalize_list/1)
  end

  defp normalize_list(nil), do: []
  defp normalize_list(list) when is_list(list), do: list
end
