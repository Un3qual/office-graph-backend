defmodule OfficeGraphWeb.GraphQL.OperatorWorkflow.Queries do
  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias Absinthe.Relay.Connection
  alias OfficeGraph.Projections
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.RequestSession

  object :operator_workflow_queries do
    field :operator_inbox, non_null(:operator_inbox) do
      arg(:limit, :integer)
      arg(:after_cursor, :string)

      resolve(fn args, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, inbox} <- Projections.operator_inbox(session_context, args) do
          {:ok, inbox}
        else
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    connection field :operator_workflow_items,
                 node_type: :operator_workflow_item,
                 paginate: :forward do
      resolve(fn args, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, :forward, limit} <- Connection.limit(args, 100),
             {:ok, page} <-
               Projections.operator_workflow_items_page(session_context,
                 limit: limit,
                 after_cursor: Map.get(args, :after)
               ) do
          {:ok, connection} =
            Connection.from_slice(page.row_edges, 0,
              has_next_page: page.has_next_page?,
              has_previous_page: page.has_previous_page?
            )

          {:ok, connection}
        else
          {:ok, _direction, _limit} ->
            Errors.to_absinthe({:error, {:invalid_field, :first}})

          {:error, {:invalid_field, :after_cursor}} ->
            Errors.to_absinthe({:error, {:invalid_field, :pagination}})

          {:error, reason} when is_binary(reason) ->
            Errors.to_absinthe({:error, {:invalid_field, :pagination}})

          error ->
            Errors.to_absinthe(error)
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

    field :operator_packet_workspace, non_null(:operator_packet_workspace) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, workspace} <- Projections.packet_workspace(session_context, id) do
          {:ok, workspace}
        else
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_packet_create_affordance, non_null(:operator_command_affordance) do
      resolve(fn _args, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, affordance} <- Projections.packet_create_affordance(session_context) do
          {:ok, affordance}
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
