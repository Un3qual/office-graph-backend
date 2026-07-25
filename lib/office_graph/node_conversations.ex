defmodule OfficeGraph.NodeConversations do
  @moduledoc """
  Public boundary for run-aware graph conversations and message provenance.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Identity,
      OfficeGraph.Operations,
      OfficeGraph.Projections,
      OfficeGraph.Repo,
      OfficeGraph.Runs,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.{Authorization, Operations, Repo, Runs}
  alias OfficeGraph.NodeConversations.{Conversation, ConversationMessage}
  alias OfficeGraph.Projections.CommandAffordance

  require Ash.Query

  @conversation_action "conversation.start"
  @message_action "conversation.message.create"
  @purpose "agent_runtime"
  @visibility "run_participants"
  @invocation_control_capabilities ~w(agent.invoke)
  @terminal_execution_states ~w(completed failed cancelled)

  def start(session_context, operation, %{run_id: run_id, graph_item_id: graph_item_id}) do
    attrs = %{run_id: run_id, graph_item_id: graph_item_id}

    with :ok <- validate_human_operation(session_context, operation, @conversation_action, attrs),
         :ok <- authorize_write(session_context, operation),
         {:ok, _run} <- Runs.validate_conversation_scope(session_context, run_id, graph_item_id) do
      Repo.transaction(fn ->
        _operation = lock_operation!(operation.id)

        lock_conversation_scope!(
          session_context.organization_id,
          session_context.workspace_id,
          run_id,
          graph_item_id
        )

        case read_conversation(session_context, run_id, graph_item_id, lock?: true) do
          {:ok, nil} ->
            Repo.ash_create!(Conversation, %{
              id: Ecto.UUID.generate(),
              organization_id: session_context.organization_id,
              workspace_id: session_context.workspace_id,
              graph_item_id: graph_item_id,
              run_id: run_id,
              created_by_principal_id: session_context.principal_id,
              operation_id: operation.id,
              purpose: @purpose,
              visibility: @visibility,
              state: "active",
              state_version: 1
            })

          {:ok, conversation} ->
            conversation

          {:error, error} ->
            Repo.rollback(error)
        end
      end)
    end
  end

  def start(_session_context, _operation, _attrs), do: {:error, :forbidden}

  def append_human_message(session_context, operation, attrs) when is_map(attrs) do
    with :ok <- validate_human_operation(session_context, operation, @message_action, attrs),
         {:ok, normalized} <- normalize_human_message(attrs),
         :ok <- authorize_write(session_context, operation) do
      Repo.transaction(fn ->
        _operation = lock_operation!(operation.id)
        conversation = lock_conversation!(session_context, normalized.conversation_id)
        validate_active_conversation!(conversation)
        validate_message_linkage!(session_context, normalized)

        case existing_message_for_operation(operation.id) do
          nil -> create_human_message!(session_context, operation, conversation, normalized)
          message -> validate_human_message_replay!(message, session_context, normalized)
        end
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
           read_agent_state(session_context, run_id, graph_item_id) do
      command_affordances =
        command_affordances(session_context, conversation, agent_state, run, graph_item_id)

      {:ok,
       agent_state
       |> Map.drop([:invocation_target])
       |> Map.merge(%{
         type: "operator_run_conversation",
         allowed_next_actions: CommandAffordance.enabled_identities(command_affordances),
         command_affordances: command_affordances,
         conversation: project_conversation(conversation),
         messages: Enum.map(messages, &project_message(&1, referenced_context))
       })
       |> Map.put(:source_watermark, source_watermark(conversation, messages, agent_state))}
    end
  end

  def project(_session_context, _run_id, _graph_item_id), do: {:error, :forbidden}

  def append_agent_message(operation, execution, context_package, step_key, body)
      when is_map(operation) and is_map(execution) and is_map(context_package) and
             is_binary(step_key) and is_binary(body) do
    with :ok <- validate_agent_operation(operation, execution, context_package, step_key) do
      conversation = get_or_create_conversation!(operation, execution)

      case existing_agent_message(execution.id, step_key) do
        nil ->
          Repo.ash_create!(ConversationMessage, %{
            id: Ecto.UUID.generate(),
            conversation_id: conversation.id,
            execution_id: execution.id,
            author_principal_id: execution.agent_principal_id,
            context_package_id: context_package.id,
            step_key: step_key,
            operation_id: operation.id,
            source: "agent",
            visibility: "run_participants",
            body: body,
            body_hash: digest(body)
          })

        message ->
          if message.operation_id == operation.id and
               message.context_package_id == context_package.id and
               message.body_hash == digest(body),
             do: message,
             else: Repo.rollback(:agent_message_replay_conflict)
      end
    end
  end

  defp get_or_create_conversation!(operation, execution) do
    lock_conversation_scope!(
      execution.organization_id,
      execution.workspace_id,
      execution.run_id,
      execution.graph_item_id
    )

    Conversation
    |> Ash.Query.filter(
      organization_id == ^execution.organization_id and workspace_id == ^execution.workspace_id and
        run_id == ^execution.run_id and graph_item_id == ^execution.graph_item_id and
        purpose == @purpose
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil ->
        Repo.ash_create!(Conversation, %{
          id: Ecto.UUID.generate(),
          organization_id: execution.organization_id,
          workspace_id: execution.workspace_id,
          graph_item_id: execution.graph_item_id,
          run_id: execution.run_id,
          created_by_principal_id: execution.agent_principal_id,
          operation_id: operation.id,
          purpose: @purpose,
          visibility: @visibility,
          state: "active",
          state_version: 1
        })

      conversation ->
        conversation
    end
  end

  defp existing_agent_message(execution_id, step_key) do
    ConversationMessage
    |> Ash.Query.filter(execution_id == ^execution_id and step_key == ^step_key)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
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

  defp authorize_write(session_context, operation) do
    Authorization.authorize_operation(session_context, operation, :conversation_write,
      organization_id: session_context.organization_id
    )
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

  defp lock_operation!(operation_id) do
    case Operations.lock_operation(operation_id) do
      {:ok, operation} -> operation
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp read_conversation(session_context, run_id, graph_item_id, opts \\ []) do
    Conversation
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and run_id == ^run_id and
        graph_item_id == ^graph_item_id and purpose == ^@purpose
    )
    |> maybe_lock(opts[:lock?])
    |> Ash.read_one(authorize?: false)
  end

  defp maybe_lock(query, true), do: Ash.Query.lock(query, :for_update)
  defp maybe_lock(query, _lock?), do: query

  defp lock_conversation!(session_context, conversation_id) do
    Conversation
    |> Ash.Query.filter(
      id == ^conversation_id and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id and purpose == ^@purpose
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> Repo.rollback(:forbidden)
      {:ok, conversation} -> conversation
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp validate_active_conversation!(%Conversation{state: "active"}), do: :ok

  defp validate_active_conversation!(%Conversation{id: id, state: state}) do
    Repo.rollback({:conversation_not_active, id, state})
  end

  defp validate_message_linkage!(session_context, normalized) do
    case normalized do
      %{
        contribution_kind: "comment",
        proposed_graph_change_id: nil,
        domain_action_operation_id: nil
      } ->
        :ok

      %{
        contribution_kind: "proposal",
        proposed_graph_change_id: proposal_id,
        domain_action_operation_id: nil
      }
      when is_binary(proposal_id) ->
        validate_proposal_scope!(session_context, proposal_id)

      %{
        contribution_kind: "domain_action",
        proposed_graph_change_id: nil,
        domain_action_operation_id: operation_id
      }
      when is_binary(operation_id) ->
        validate_domain_operation_scope!(session_context, operation_id)

      %{contribution_kind: kind} ->
        Repo.rollback({:invalid_conversation_message_linkage, kind})
    end
  end

  defp validate_proposal_scope!(session_context, proposal_id) do
    case Repo.query(
           """
           SELECT 1
           FROM proposed_graph_changes
           WHERE id = $1 AND organization_id = $2 AND workspace_id = $3
           """,
           [
             Ecto.UUID.dump!(proposal_id),
             Ecto.UUID.dump!(session_context.organization_id),
             Ecto.UUID.dump!(session_context.workspace_id)
           ]
         ) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, _missing} -> Repo.rollback(:forbidden)
      {:error, _storage_error} -> Repo.rollback(:integration_storage_unavailable)
    end
  end

  defp validate_domain_operation_scope!(session_context, operation_id) do
    case Operations.read_operation(operation_id) do
      {:ok, operation}
      when operation.organization_id == session_context.organization_id and
             operation.workspace_id == session_context.workspace_id and
             operation.action not in [@conversation_action, @message_action] ->
        :ok

      {:ok, _operation} ->
        Repo.rollback(:forbidden)

      {:error, {:not_found, _resource, _id}} ->
        Repo.rollback(:forbidden)

      {:error, _storage_error} ->
        Repo.rollback(:integration_storage_unavailable)
    end
  end

  defp existing_message_for_operation(operation_id) do
    ConversationMessage
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one!(authorize?: false)
  end

  defp create_human_message!(session_context, operation, conversation, normalized) do
    Repo.ash_create!(ConversationMessage, %{
      id: Ecto.UUID.generate(),
      conversation_id: conversation.id,
      author_principal_id: session_context.principal_id,
      operation_id: operation.id,
      proposed_graph_change_id: normalized.proposed_graph_change_id,
      domain_action_operation_id: normalized.domain_action_operation_id,
      source: "human",
      visibility: @visibility,
      body: normalized.body,
      body_hash: digest(normalized.body)
    })
  end

  defp validate_human_message_replay!(message, session_context, normalized) do
    if message.source == "human" and
         message.author_principal_id == session_context.principal_id and
         message.body_hash == digest(normalized.body) and
         message.proposed_graph_change_id == normalized.proposed_graph_change_id and
         message.domain_action_operation_id == normalized.domain_action_operation_id do
      message
    else
      Repo.rollback({:conversation_message_replay_conflict, message.id})
    end
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
    case Repo.query(
           """
           SELECT package.id::text, package.version, entry.posture, entry.rationale_code,
                  entry.ordinal
           FROM agent_context_packages AS package
           LEFT JOIN agent_context_entries AS entry
             ON entry.context_package_id = package.id
            AND entry.organization_id = $2
            AND entry.workspace_id = $3
           WHERE package.id = ANY($1::uuid[])
             AND package.organization_id = $2
             AND package.workspace_id = $3
             AND package.run_id = $4
             AND package.selected_graph_item_id = $5
           ORDER BY package.id, entry.ordinal
           """,
           [
             Enum.map(package_ids, &Ecto.UUID.dump!/1),
             Ecto.UUID.dump!(session_context.organization_id),
             Ecto.UUID.dump!(session_context.workspace_id),
             Ecto.UUID.dump!(conversation.run_id),
             Ecto.UUID.dump!(conversation.graph_item_id)
           ]
         ) do
      {:ok, %{rows: rows}} -> {:ok, context_package_map(rows)}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp context_package_map(rows) do
    rows
    |> Enum.reduce(%{}, fn [package_id, version, posture, rationale_code, _ordinal], acc ->
      package =
        Map.get(acc, package_id, %{
          visibility: "visible",
          package_id: package_id,
          version: version,
          entries: []
        })

      entries =
        if is_binary(posture),
          do: [%{posture: posture, rationale_code: rationale_code} | package.entries],
          else: package.entries

      Map.put(acc, package_id, %{package | entries: entries})
    end)
    |> Map.new(fn {package_id, package} ->
      {package_id, %{package | entries: Enum.reverse(package.entries)}}
    end)
  end

  defp project_conversation(nil), do: nil

  defp project_conversation(conversation) do
    Map.take(conversation, [
      :id,
      :run_id,
      :graph_item_id,
      :created_by_principal_id,
      :operation_id,
      :purpose,
      :visibility,
      :state,
      :state_version,
      :inserted_at,
      :updated_at
    ])
  end

  defp project_message(message, referenced_context) do
    message
    |> Map.take([
      :id,
      :source,
      :body,
      :visibility,
      :author_principal_id,
      :execution_id,
      :context_package_id,
      :operation_id,
      :proposed_graph_change_id,
      :domain_action_operation_id,
      :inserted_at
    ])
    |> Map.put(
      :referenced_context,
      referenced_context_projection(message.context_package_id, referenced_context)
    )
  end

  defp referenced_context_projection(nil, _referenced_context), do: nil

  defp referenced_context_projection(package_id, referenced_context) do
    Map.get(referenced_context, package_id, %{visibility: "redacted"})
  end

  defp read_agent_state(session_context, run_id, graph_item_id) do
    with {:ok, %{rows: execution_rows}} <-
           Repo.query(
             """
             SELECT id::text, state, state_version, current_step_key, attempt_count,
                    failure_code, requested_outcome, invocation_mode, origin, autonomy_mode,
                    organization_binding_id::text, inserted_at, updated_at
             FROM (
               SELECT execution.*
               FROM agent_executions AS execution
               WHERE execution.organization_id = $1 AND execution.workspace_id = $2
                 AND execution.run_id = $3 AND execution.graph_item_id = $4
               ORDER BY
                 CASE WHEN execution.state IN ('completed', 'failed', 'cancelled') THEN 1 ELSE 0 END,
                 execution.inserted_at DESC,
                 execution.id DESC
               LIMIT 100
             ) AS bounded_executions
             ORDER BY inserted_at, id
             """,
             scope_params(session_context, run_id, graph_item_id)
           ),
         {:ok, %{rows: approval_rows}} <-
           Repo.query(
             """
             SELECT request.id::text, request.execution_id::text, request.step_key,
                    request.requested_action, request.reason, request.scope_type,
                    request.scope_id::text, request.capability_key, request.sensitivity,
                    request.external_write, request.state, request.version, request.expires_at,
                    request.resolution_reason, request.inserted_at, request.updated_at
             FROM (
               SELECT request.*
               FROM agent_approval_requests AS request
               JOIN agent_executions AS execution ON execution.id = request.execution_id
               WHERE execution.organization_id = $1 AND execution.workspace_id = $2
                 AND execution.run_id = $3 AND execution.graph_item_id = $4
               ORDER BY
                 CASE WHEN request.state = 'pending' THEN 0 ELSE 1 END,
                 request.inserted_at DESC,
                 request.id DESC
               LIMIT 100
             ) AS request
             ORDER BY request.inserted_at, request.id
             """,
             scope_params(session_context, run_id, graph_item_id)
           ),
         {:ok, %{rows: expansion_rows}} <-
           Repo.query(
             """
             SELECT request.id::text, request.execution_id::text, request.step_key,
                    request.target_resource_type, request.target_resource_id::text,
                    request.target_scope_type, request.target_scope_id::text,
                    request.access_mode, request.capability_key, request.reason,
                    request.sensitivity, request.expected_duration_seconds, request.state,
                    request.version, request.expires_at, request.resolution_reason,
                    request.inserted_at, request.updated_at
             FROM (
               SELECT request.*
               FROM agent_context_expansion_requests AS request
               JOIN agent_executions AS execution ON execution.id = request.execution_id
               WHERE execution.organization_id = $1 AND execution.workspace_id = $2
                 AND execution.run_id = $3 AND execution.graph_item_id = $4
               ORDER BY
                 CASE WHEN request.state = 'pending' THEN 0 ELSE 1 END,
                 request.inserted_at DESC,
                 request.id DESC
               LIMIT 100
             ) AS request
             ORDER BY request.inserted_at, request.id
             """,
             scope_params(session_context, run_id, graph_item_id)
           ),
         {:ok, %{rows: invocation_rows}} <-
           Repo.query(
             """
             SELECT binding.id::text, definition.requested_capabilities,
                    definition.default_autonomy_mode
             FROM agent_organization_bindings AS binding
             JOIN agent_definitions AS definition ON definition.id = binding.definition_id
             WHERE binding.organization_id = $1 AND binding.workspace_id = $2
               AND binding.lifecycle_state = 'active'
               AND definition.lifecycle_state = 'active'
               AND definition.key = 'run-review'
             ORDER BY binding.inserted_at, binding.id
             LIMIT 1
             """,
             Enum.take(scope_params(session_context, run_id, graph_item_id), 2)
           ) do
      {:ok,
       %{
         executions: Enum.map(execution_rows, &execution_projection/1),
         approval_requests: Enum.map(approval_rows, &approval_projection/1),
         context_expansion_requests: Enum.map(expansion_rows, &context_expansion_projection/1),
         invocation_target: invocation_target(invocation_rows)
       }}
    else
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp scope_params(session_context, run_id, graph_item_id) do
    [
      Ecto.UUID.dump!(session_context.organization_id),
      Ecto.UUID.dump!(session_context.workspace_id),
      Ecto.UUID.dump!(run_id),
      Ecto.UUID.dump!(graph_item_id)
    ]
  end

  defp execution_projection([
         id,
         state,
         state_version,
         current_step_key,
         attempt_count,
         failure_code,
         requested_outcome,
         invocation_mode,
         origin,
         autonomy_mode,
         binding_id,
         inserted_at,
         updated_at
       ]) do
    %{
      id: id,
      state: state,
      state_version: state_version,
      current_step_key: current_step_key,
      attempt_count: attempt_count,
      failure_code: failure_code,
      requested_outcome: requested_outcome,
      invocation_mode: invocation_mode,
      origin: origin,
      autonomy_mode: autonomy_mode,
      binding_id: binding_id,
      inserted_at: utc_datetime(inserted_at),
      updated_at: utc_datetime(updated_at)
    }
  end

  defp approval_projection([
         id,
         execution_id,
         step_key,
         requested_action,
         reason,
         scope_type,
         scope_id,
         capability_key,
         sensitivity,
         external_write,
         state,
         version,
         expires_at,
         resolution_reason,
         inserted_at,
         updated_at
       ]) do
    %{
      id: id,
      execution_id: execution_id,
      step_key: step_key,
      requested_action: requested_action,
      reason: reason,
      scope_type: scope_type,
      scope_id: scope_id,
      capability_key: capability_key,
      sensitivity: sensitivity,
      external_write: external_write,
      state: state,
      version: version,
      expires_at: utc_datetime(expires_at),
      resolution_reason: resolution_reason,
      inserted_at: utc_datetime(inserted_at),
      updated_at: utc_datetime(updated_at)
    }
  end

  defp context_expansion_projection([
         id,
         execution_id,
         step_key,
         target_resource_type,
         target_resource_id,
         target_scope_type,
         target_scope_id,
         access_mode,
         capability_key,
         reason,
         sensitivity,
         expected_duration_seconds,
         state,
         version,
         expires_at,
         resolution_reason,
         inserted_at,
         updated_at
       ]) do
    %{
      id: id,
      execution_id: execution_id,
      step_key: step_key,
      target_resource_type: target_resource_type,
      target_resource_id: target_resource_id,
      target_scope_type: target_scope_type,
      target_scope_id: target_scope_id,
      access_mode: access_mode,
      capability_key: capability_key,
      reason: reason,
      sensitivity: sensitivity,
      expected_duration_seconds: expected_duration_seconds,
      state: state,
      version: version,
      expires_at: utc_datetime(expires_at),
      resolution_reason: resolution_reason,
      inserted_at: utc_datetime(inserted_at),
      updated_at: utc_datetime(updated_at)
    }
  end

  defp utc_datetime(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp utc_datetime(%DateTime{} = value), do: value
  defp utc_datetime(nil), do: nil

  defp invocation_target([[binding_id, requested_capabilities, autonomy_mode]]) do
    delegated_capabilities =
      requested_capabilities
      |> Kernel.--(@invocation_control_capabilities)
      |> Enum.sort()

    if delegated_capabilities != [] do
      %{
        binding_id: binding_id,
        requested_capabilities: delegated_capabilities,
        autonomy_mode: autonomy_mode
      }
    end
  end

  defp invocation_target(_rows), do: nil

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

  defp lock_conversation_scope!(organization_id, workspace_id, run_id, graph_item_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
      "node-conversation:#{organization_id}:#{workspace_id}:#{run_id}:#{graph_item_id}:#{@purpose}"
    ])
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
