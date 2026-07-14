defmodule OfficeGraphWeb.GraphQL.OperatorWorkflow.Queries do
  use Absinthe.Schema.Notation
  use Absinthe.Relay.Schema.Notation, :modern

  alias Absinthe.Relay.Connection
  alias OfficeGraph.Projections
  alias OfficeGraph.WorkGraph
  alias OfficeGraphWeb.GraphQL.Common.Errors
  alias OfficeGraphWeb.RequestSession

  object :operator_workflow_queries do
    field :graph_relationships, non_null(list_of(non_null(:graph_relationship_view))) do
      arg(:item_id, non_null(:id))
      arg(:direction, :string)
      arg(:definition_keys, list_of(non_null(:string)))
      arg(:lifecycle, :string)
      arg(:limit, :integer)

      resolve(fn args, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, item_id} <- normalize_graph_item_id(args.item_id),
             {:ok, opts} <- relationship_opts(args),
             {:ok, relationships} <-
               WorkGraph.list_relationships(session_context, item_id, opts) do
          {:ok, relationships}
        else
          {:error, {:invalid_relationship_option, field}} ->
            Errors.to_absinthe({:error, {:invalid_field, field}})

          error ->
            Errors.to_absinthe(error)
        end
      end)
    end

    connection field :operator_workflow_items,
                 node_type: :operator_workflow_item,
                 paginate: :forward do
      resolve(fn args, resolution ->
        with :ok <- validate_first(args),
             {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
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

    connection field :operator_relationship_details,
                 node_type: :operator_relationship_detail,
                 paginate: :forward do
      arg(:id, non_null(:id))

      resolve(fn args, resolution ->
        with :ok <- validate_first(args),
             {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, :forward, limit} <- Connection.limit(args, 100),
             {:ok, page} <-
               Projections.operator_relationship_details_page(session_context, args.id,
                 limit: limit,
                 after_cursor: Map.get(args, :after)
               ) do
          {:ok,
           %{
             edges: page.edges,
             page_info: %{
               has_next_page: page.has_next_page?,
               has_previous_page: page.has_previous_page?,
               start_cursor: page.edges |> List.first() |> then(&(&1 && &1.cursor)),
               end_cursor: page.edges |> List.last() |> then(&(&1 && &1.cursor))
             }
           }}
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
             {:ok, packet_id} <- normalize_work_packet_id(id),
             {:ok, workspace} <- Projections.packet_workspace(session_context, packet_id) do
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

    field :operator_manual_intake_affordance, non_null(:operator_command_affordance) do
      resolve(fn _args, resolution ->
        with {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, affordance} <- Projections.manual_intake_affordance(session_context) do
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

    connection field :operator_run_command_option_page,
                 node_type: :operator_run_command_option_choice,
                 paginate: :forward do
      arg(:id, non_null(:id))
      arg(:kind, non_null(:string))

      resolve(fn args, resolution ->
        with :ok <- validate_first(args),
             {:ok, session_context} <- RequestSession.resolve_resolution(resolution),
             {:ok, :forward, limit} <- Connection.limit(args, 100),
             {:ok, page} <-
               Projections.operator_run_command_option_page(
                 session_context,
                 args.id,
                 args.kind,
                 limit: limit,
                 after_cursor: Map.get(args, :after)
               ) do
          {:ok,
           %{
             edges: page.edges,
             page_info: %{
               has_next_page: page.has_next_page?,
               has_previous_page: page.has_previous_page?,
               start_cursor: page.edges |> List.first() |> then(&(&1 && &1.cursor)),
               end_cursor: page.edges |> List.last() |> then(&(&1 && &1.cursor))
             }
           }}
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

  defp validate_first(%{first: first}) when is_integer(first) and first < 0,
    do: {:error, {:invalid_field, :first}}

  defp validate_first(_args), do: :ok

  defp normalize_packet_readiness_input(input) do
    input
    |> Map.update(:source_graph_item_ids, [], &normalize_list/1)
    |> Map.update(:verification_check_ids, [], &normalize_list/1)
  end

  defp normalize_list(nil), do: []
  defp normalize_list(list) when is_list(list), do: list

  defp normalize_work_packet_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _id} ->
        {:ok, id}

      :error ->
        schema = Module.concat(["OfficeGraphWeb.GraphQL.Schema"])

        case Absinthe.Relay.Node.from_global_id(id, schema) do
          {:ok, %{type: :work_packet, id: packet_id}} -> {:ok, packet_id}
          _other -> {:error, {:invalid_field, :id}}
        end
    end
  end

  defp normalize_graph_item_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, graph_item_id} ->
        {:ok, graph_item_id}

      :error ->
        schema = Module.concat(["OfficeGraphWeb.GraphQL.Schema"])

        case Absinthe.Relay.Node.from_global_id(id, schema) do
          {:ok, %{type: :graph_item, id: graph_item_id}} -> {:ok, graph_item_id}
          _other -> {:error, {:invalid_field, :item_id}}
        end
    end
  end

  defp relationship_opts(args) do
    with {:ok, direction} <- normalize_relationship_direction(Map.get(args, :direction)),
         {:ok, lifecycle} <- normalize_relationship_lifecycle(Map.get(args, :lifecycle)) do
      {:ok,
       [
         direction: direction,
         definition_keys: Map.get(args, :definition_keys),
         lifecycle: lifecycle,
         limit: Map.get(args, :limit, 25)
       ]}
    end
  end

  defp normalize_relationship_direction(nil), do: {:ok, :both}

  defp normalize_relationship_direction(direction) when is_binary(direction) do
    case String.downcase(direction) do
      "incoming" -> {:ok, :incoming}
      "outgoing" -> {:ok, :outgoing}
      "both" -> {:ok, :both}
      _direction -> {:error, {:invalid_field, :direction}}
    end
  end

  defp normalize_relationship_direction(_direction),
    do: {:error, {:invalid_field, :direction}}

  defp normalize_relationship_lifecycle(nil), do: {:ok, "active"}

  defp normalize_relationship_lifecycle(lifecycle) when lifecycle in ["active", "archived"],
    do: {:ok, lifecycle}

  defp normalize_relationship_lifecycle(_lifecycle),
    do: {:error, {:invalid_field, :lifecycle}}
end
