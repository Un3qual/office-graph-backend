defmodule OfficeGraph.NodeConversations do
  @moduledoc """
  Public boundary for run-aware graph conversations and message provenance.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.CommandSupport,
      OfficeGraph.Identity,
      OfficeGraph.Operations,
      OfficeGraph.Projections,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Runs,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.{Authorization, Operations, Runs}

  alias OfficeGraph.NodeConversations.{
    ActionSupport,
    Conversation,
    ConversationMessage
  }

  alias OfficeGraph.NodeConversations.Projections.ConversationProjection
  alias OfficeGraph.Projections.CommandAffordance

  require Ash.Query

  @purpose "agent_runtime"
  @terminal_execution_states ~w(completed failed cancelled)

  def start(session_context, operation, %{run_id: run_id, graph_item_id: graph_item_id}) do
    attrs = %{run_id: run_id, graph_item_id: graph_item_id}

    with :ok <- validate_human_operation(session_context, operation, "conversation.start", attrs) do
      ActionSupport.run(fn ->
        Conversation
        |> Ash.ActionInput.for_action(:persist_start_contract, %{
          operation_id: operation.id,
          run_id: run_id,
          graph_item_id: graph_item_id
        })
        |> Ash.run_action(actor: session_context, authorize?: false)
      end)
    end
  end

  def start(_session_context, _operation, _attrs), do: {:error, :forbidden}

  def append_human_message(session_context, operation, attrs) when is_map(attrs) do
    with :ok <-
           validate_human_operation(
             session_context,
             operation,
             "conversation.message.create",
             attrs
           ),
         {:ok, normalized} <- normalize_human_message(attrs) do
      ActionSupport.run(fn ->
        ConversationMessage
        |> Ash.ActionInput.for_action(
          :persist_human_message_contract,
          Map.put(normalized, :operation_id, operation.id)
        )
        |> Ash.run_action(actor: session_context, authorize?: false)
      end)
    end
  end

  def append_human_message(_session_context, _operation, _attrs), do: {:error, :forbidden}

  def project(session_context, run_id, graph_item_id)
      when is_binary(run_id) and is_binary(graph_item_id) do
    with :ok <-
           Authorization.authorize_projection(session_context, :skeleton_read,
             organization_id: session_context.organization_id
           ),
         {:ok, run} <- Runs.validate_conversation_scope(session_context, run_id, graph_item_id),
         {:ok, conversation} <- read_conversation(session_context, run_id, graph_item_id),
         {:ok, messages} <- read_messages(conversation),
         {:ok, referenced_context} <-
           read_referenced_context(session_context, conversation, messages),
         {:ok, agent_state} <-
           ConversationProjection.read_agent_state(session_context, run, graph_item_id) do
      command_affordances =
        command_affordances(session_context, conversation, agent_state, run, graph_item_id)

      {:ok,
       agent_state
       |> Map.from_struct()
       |> Map.drop([
         :invocation_target,
         :executions,
         :approval_requests,
         :context_expansion_requests
       ])
       |> Map.merge(%{
         type: "operator_run_conversation",
         run_id: run_id,
         graph_item_id: graph_item_id,
         allowed_next_actions: CommandAffordance.enabled_identities(command_affordances),
         command_affordances: command_affordances,
         message_contexts: Enum.map(messages, &project_message_context(&1, referenced_context))
       })
       |> Map.put(:source_watermark, source_watermark(conversation, messages, agent_state))}
    end
  end

  def project(_session_context, _run_id, _graph_item_id), do: {:error, :forbidden}

  def append_agent_message(operation, execution, context_package, step_key, body)
      when is_map(operation) and is_map(execution) and is_map(context_package) and
             is_binary(step_key) and is_binary(body) do
    with :ok <- validate_agent_operation(operation, execution, context_package, step_key) do
      case ActionSupport.run(fn ->
             ConversationMessage
             |> Ash.ActionInput.for_action(:persist_agent_message_contract, %{
               operation_id: operation.id,
               execution: execution,
               context_package: context_package,
               step_key: step_key,
               body: body
             })
             |> Ash.run_action(authorize?: false)
           end) do
        {:ok, message} -> message
        {:error, _reason} = error -> error
      end
    end
  end

  defp validate_agent_operation(operation, execution, context_package, step_key) do
    Operations.validate_agent_output_operation(operation, execution, context_package, step_key)
  end

  defp validate_human_operation(session_context, operation, action, attrs) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- Operations.validate_operation_action(operation, action),
         :ok <- Operations.validate_command_replay(operation, attrs) do
      :ok
    end
  end

  defp normalize_human_message(attrs) do
    body = Map.get(attrs, :body)
    contribution_kind = Map.get(attrs, :contribution_kind)

    if is_binary(Map.get(attrs, :conversation_id)) and is_binary(body) and
         String.trim(body) != "" and byte_size(body) <= 32_768 and
         contribution_kind in ["comment", "proposal", "domain_action"] do
      {:ok,
       %{
         conversation_id: attrs.conversation_id,
         body: body,
         contribution_kind: contribution_kind,
         proposed_graph_change_id: Map.get(attrs, :proposed_graph_change_id),
         domain_action_operation_id: Map.get(attrs, :domain_action_operation_id)
       }}
    else
      {:error, {:invalid_field, invalid_human_message_field(attrs)}}
    end
  end

  defp invalid_human_message_field(attrs) do
    cond do
      not is_binary(Map.get(attrs, :conversation_id)) ->
        :conversation_id

      not is_binary(Map.get(attrs, :body)) or String.trim(Map.get(attrs, :body, "")) == "" ->
        :body

      byte_size(Map.get(attrs, :body, "")) > 32_768 ->
        :body

      true ->
        :contribution_kind
    end
  end

  defp read_conversation(session_context, run_id, graph_item_id) do
    Conversation
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and run_id == ^run_id and
        graph_item_id == ^graph_item_id and purpose == ^@purpose
    )
    |> Ash.read_one(authorize?: false)
  end

  defp read_messages(nil), do: {:ok, []}

  defp read_messages(conversation) do
    ConversationMessage
    |> Ash.Query.filter(conversation_id == ^conversation.id)
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(100)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      {:error, _reason} = error -> error
    end
  end

  defp read_referenced_context(_session_context, nil, _messages), do: {:ok, %{}}

  defp read_referenced_context(session_context, conversation, messages) do
    package_ids =
      messages
      |> Enum.map(& &1.context_package_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if package_ids == [] do
      {:ok, %{}}
    else
      read_visible_context_packages(session_context, conversation, package_ids)
    end
  end

  defp read_visible_context_packages(session_context, conversation, package_ids) do
    ConversationProjection.read_visible_context_packages(
      session_context,
      conversation,
      package_ids
    )
  end

  defp project_message_context(message, referenced_context) do
    %{
      message_id: message.id,
      referenced_context:
        referenced_context_projection(message.context_package_id, referenced_context)
    }
  end

  defp referenced_context_projection(nil, _referenced_context), do: nil

  defp referenced_context_projection(package_id, referenced_context) do
    Map.get(referenced_context, package_id, %{visibility: "redacted"})
  end

  defp command_affordances(session_context, conversation, agent_state, run, graph_item_id) do
    now = DateTime.utc_now()

    [
      conversation_affordance(session_context, conversation, run.id, graph_item_id),
      invocation_affordance(
        session_context,
        agent_state.invocation_target,
        run,
        graph_item_id
      ),
      cancellation_affordance(session_context, agent_state.executions),
      approval_affordance(session_context, agent_state.approval_requests, now),
      context_expansion_affordance(
        session_context,
        agent_state.context_expansion_requests,
        now
      )
    ]
  end

  defp conversation_affordance(session_context, nil, run_id, graph_item_id) do
    capability_affordance(
      session_context,
      :conversation_write,
      "start_run_conversation",
      "Start a focused conversation for this run and graph item.",
      required_fields: ["run_id", "graph_item_id"],
      input_defaults: [
        CommandAffordance.input_default("run_id", run_id),
        CommandAffordance.input_default("graph_item_id", graph_item_id)
      ],
      target_ids: [
        CommandAffordance.target_id("run", run_id),
        CommandAffordance.target_id("graph_item", graph_item_id)
      ]
    )
  end

  defp conversation_affordance(
         session_context,
         %{state: "active", id: conversation_id},
         _run_id,
         _graph_item_id
       ) do
    capability_affordance(
      session_context,
      :conversation_write,
      "append_conversation_message",
      "Add a human contribution to this run conversation.",
      required_fields: ["conversation_id", "body", "contribution_kind"],
      input_defaults: [CommandAffordance.input_default("conversation_id", conversation_id)],
      target_ids: [CommandAffordance.target_id("conversation", conversation_id)]
    )
  end

  defp conversation_affordance(_session_context, conversation, _run_id, _graph_item_id) do
    CommandAffordance.disabled(
      "append_conversation_message",
      "This conversation is no longer active.",
      target_ids: [CommandAffordance.target_id("conversation", conversation.id)]
    )
  end

  defp invocation_affordance(session_context, target, run, graph_item_id)
       when not is_nil(target) do
    case Runs.validate_agent_invocation_scope(run, graph_item_id, target.autonomy_mode) do
      :ok ->
        authorized_invocation_affordance(session_context, target, run.id, graph_item_id)

      {:error, _reason} ->
        CommandAffordance.disabled(
          "invoke_agent",
          "This run context no longer permits agent invocation."
        )
    end
  end

  defp invocation_affordance(_session_context, nil, _run, _graph_item_id) do
    CommandAffordance.disabled(
      "invoke_agent",
      "No approved run review agent is bound to this workspace."
    )
  end

  defp authorized_invocation_affordance(session_context, target, run_id, graph_item_id) do
    with true <- CommandAffordance.authorized?(session_context, :agent_invoke),
         {:ok, granted} <-
           Authorization.intersect_principal_capabilities(
             session_context.principal_id,
             session_context.organization_id,
             session_context.workspace_id,
             target.requested_capabilities
           ),
         [] <- target.requested_capabilities -- granted do
      CommandAffordance.enabled(
        "invoke_agent",
        "Invoke the approved run review agent for this run context.",
        required_fields: [
          "binding_id",
          "run_id",
          "graph_item_id",
          "requested_outcome",
          "requested_capabilities",
          "autonomy_mode"
        ],
        input_defaults: [
          CommandAffordance.input_default("binding_id", target.binding_id),
          CommandAffordance.input_default("run_id", run_id),
          CommandAffordance.input_default("graph_item_id", graph_item_id),
          CommandAffordance.input_default(
            "requested_outcome",
            "Review the selected run, work packet, graph context, checks, and evidence, then propose bounded follow-up work."
          ),
          CommandAffordance.input_default(
            "requested_capabilities",
            target.requested_capabilities
          ),
          CommandAffordance.input_default("autonomy_mode", target.autonomy_mode)
        ],
        target_ids: [
          CommandAffordance.target_id("agent_organization_binding", target.binding_id)
        ]
      )
    else
      _unauthorized_or_unavailable -> CommandAffordance.policy_restricted("invoke_agent")
    end
  end

  defp cancellation_affordance(session_context, executions) do
    active = Enum.reject(executions, &(&1.state in @terminal_execution_states))

    if active == [] do
      CommandAffordance.disabled(
        "cancel_agent_execution",
        "No active agent execution can be cancelled."
      )
    else
      capability_affordance(
        session_context,
        :agent_cancel,
        "cancel_agent_execution",
        "Cancel one active agent execution using its current version.",
        required_fields: ["execution_id", "expected_state_version"],
        target_ids: Enum.map(active, &CommandAffordance.target_id("agent_execution", &1.id))
      )
    end
  end

  defp approval_affordance(session_context, requests, now) do
    pending = Enum.filter(requests, &resolvable_request?(&1, now))

    request_affordance(
      session_context,
      :agent_approval_resolve,
      "resolve_agent_approval",
      "Resolve one exact pending agent approval request.",
      pending,
      "agent_approval_request",
      "approval_request_id"
    )
  end

  defp context_expansion_affordance(session_context, requests, now) do
    pending = Enum.filter(requests, &resolvable_request?(&1, now))

    request_affordance(
      session_context,
      :agent_context_expansion_resolve,
      "resolve_agent_context_expansion",
      "Resolve one exact pending context expansion request.",
      pending,
      "agent_context_expansion_request",
      "context_expansion_request_id"
    )
  end

  defp resolvable_request?(%{state: "pending", expires_at: %DateTime{} = expires_at}, now) do
    DateTime.compare(expires_at, now) == :gt
  end

  defp resolvable_request?(_request, _now), do: false

  defp request_affordance(
         _session_context,
         _capability,
         identity,
         explanation,
         [],
         _type,
         _request_id_field
       ) do
    CommandAffordance.disabled(identity, explanation)
  end

  defp request_affordance(
         session_context,
         capability,
         identity,
         explanation,
         pending,
         type,
         request_id_field
       ) do
    capability_affordance(
      session_context,
      capability,
      identity,
      explanation,
      required_fields: [
        request_id_field,
        "expected_version",
        "decision",
        "resolution_reason"
      ],
      target_ids: Enum.map(pending, &CommandAffordance.target_id(type, &1.id))
    )
  end

  defp capability_affordance(session_context, capability, identity, explanation, opts) do
    if CommandAffordance.authorized?(session_context, capability) do
      CommandAffordance.enabled(identity, explanation, opts)
    else
      CommandAffordance.policy_restricted(identity)
    end
  end

  defp source_watermark(conversation, messages, agent_state) do
    [
      conversation && conversation.id,
      conversation && conversation.updated_at,
      Enum.map(messages, &{&1.id, &1.inserted_at}),
      Enum.map(agent_state.executions, &{&1.id, &1.updated_at}),
      Enum.map(agent_state.approval_requests, &{&1.id, &1.updated_at}),
      Enum.map(agent_state.context_expansion_requests, &{&1.id, &1.updated_at})
    ]
    |> :erlang.term_to_binary()
    |> digest()
  end

  defp digest(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end
end
