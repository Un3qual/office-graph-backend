defmodule OfficeGraph.NodeConversations.Projections.ConversationProjection do
  @moduledoc false

  alias OfficeGraph.NodeConversations.ConversationMessage

  require Ash.Query

  @history_limit 100
  @invocation_control_capabilities ~w(agent.invoke)
  @terminal_execution_states ~w(completed failed cancelled)

  defmodule AgentState do
    @moduledoc false

    @enforce_keys [
      :executions,
      :approval_requests,
      :context_expansion_requests,
      :invocation_target
    ]

    defstruct @enforce_keys

    @type t :: %__MODULE__{
            executions: [struct()],
            approval_requests: [struct()],
            context_expansion_requests: [struct()],
            invocation_target: map() | nil
          }
  end

  def read_visible_context_packages(session_context, conversation, package_ids) do
    package_resource = related_resource!(ConversationMessage, :context_package)
    entry_resource = related_resource!(package_resource, :entries)

    entry_query =
      entry_resource
      |> Ash.Query.filter(
        organization_id == ^session_context.organization_id and
          workspace_id == ^session_context.workspace_id
      )
      |> Ash.Query.sort(ordinal: :asc)

    package_resource
    |> Ash.Query.filter(
      id in ^package_ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and run_id == ^conversation.run_id and
        selected_graph_item_id == ^conversation.graph_item_id
    )
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.load(entries: entry_query)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, packages} -> {:ok, Map.new(packages, &context_package_projection/1)}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  def read_agent_state(session_context, run, graph_item_id) do
    execution_resource = related_resource!(run.__struct__, :agent_executions)
    approval_resource = related_resource!(execution_resource, :approval_requests)
    expansion_resource = related_resource!(execution_resource, :context_expansion_requests)
    binding_resource = related_resource!(execution_resource, :organization_binding)

    with {:ok, executions} <-
           read_executions(execution_resource, session_context, run.id, graph_item_id),
         {:ok, approval_requests} <-
           read_requests(
             approval_resource,
             session_context,
             run.id,
             graph_item_id
           ),
         {:ok, context_expansion_requests} <-
           read_requests(
             expansion_resource,
             session_context,
             run.id,
             graph_item_id
           ),
         {:ok, invocation_target} <-
           read_invocation_target(binding_resource, session_context) do
      {:ok,
       %AgentState{
         executions: executions,
         approval_requests: approval_requests,
         context_expansion_requests: context_expansion_requests,
         invocation_target: invocation_target
       }}
    else
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp read_executions(resource, session_context, run_id, graph_item_id) do
    query =
      resource
      |> Ash.Query.filter(
        organization_id == ^session_context.organization_id and
          workspace_id == ^session_context.workspace_id and run_id == ^run_id and
          graph_item_id == ^graph_item_id
      )
      |> Ash.Query.sort(inserted_at: :desc, id: :desc)

    with {:ok, active} <-
           query
           |> Ash.Query.filter(state not in ^@terminal_execution_states)
           |> read_limit(@history_limit),
         {:ok, terminal} <-
           query
           |> Ash.Query.filter(state in ^@terminal_execution_states)
           |> read_limit(@history_limit - length(active)) do
      {:ok, chronological(active ++ terminal)}
    end
  end

  defp read_requests(resource, session_context, run_id, graph_item_id) do
    query =
      resource
      |> Ash.Query.filter(
        organization_id == ^session_context.organization_id and
          workspace_id == ^session_context.workspace_id and execution.run_id == ^run_id and
          execution.graph_item_id == ^graph_item_id
      )
      |> Ash.Query.sort(inserted_at: :desc, id: :desc)

    with {:ok, pending} <-
           query
           |> Ash.Query.filter(state == "pending")
           |> read_limit(@history_limit),
         {:ok, resolved} <-
           query
           |> Ash.Query.filter(state != "pending")
           |> read_limit(@history_limit - length(pending)) do
      {:ok, chronological(pending ++ resolved)}
    end
  end

  defp read_invocation_target(resource, session_context) do
    resource
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and lifecycle_state == "active" and
        definition.lifecycle_state == "active" and definition.key == "run-review"
    )
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(1)
    |> Ash.Query.load(:definition)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, [%{id: binding_id, definition: definition}]} ->
        {:ok, invocation_target(binding_id, definition)}

      {:ok, []} ->
        {:ok, nil}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp read_limit(_query, 0), do: {:ok, []}

  defp read_limit(query, limit) do
    query
    |> Ash.Query.limit(limit)
    |> Ash.read(authorize?: false)
  end

  defp chronological(records) do
    Enum.sort(records, fn left, right ->
      case DateTime.compare(left.inserted_at, right.inserted_at) do
        :lt -> true
        :gt -> false
        :eq -> left.id <= right.id
      end
    end)
  end

  defp context_package_projection(package) do
    {package.id,
     %{
       visibility: "visible",
       package_id: package.id,
       version: package.version,
       entries:
         Enum.map(package.entries, fn entry ->
           %{posture: entry.posture, rationale_code: entry.rationale_code}
         end)
     }}
  end

  defp invocation_target(binding_id, definition) do
    delegated_capabilities =
      definition.requested_capabilities
      |> Kernel.--(@invocation_control_capabilities)
      |> Enum.sort()

    if delegated_capabilities == [] do
      nil
    else
      %{
        binding_id: binding_id,
        requested_capabilities: delegated_capabilities,
        autonomy_mode: definition.default_autonomy_mode
      }
    end
  end

  defp related_resource!(resource, relationship) do
    Ash.Resource.Info.related(resource, relationship) ||
      raise ArgumentError,
            "missing Ash relationship #{inspect(resource)}.#{relationship}"
  end
end
