defmodule OfficeGraph.WorkGraph.RelationshipCommands do
  @moduledoc false

  alias OfficeGraph.{Authorization, Operations}
  alias OfficeGraph.WorkGraph.CommandActionResult
  alias OfficeGraph.WorkGraph.CommandSupport, as: Support

  alias OfficeGraph.WorkGraph.{
    GraphItem,
    GraphRelationship,
    RelationshipCyclePolicy,
    RelationshipDefinitions,
    RelationshipOperationPolicy,
    RelationshipRequest
  }

  require Ash.Query

  @run_resource Module.concat([OfficeGraph, Runs, Run])
  @integration_event_resource Module.concat([OfficeGraph, Integrations, NormalizedIntakeEvent])

  @behaviour Ash.Resource.Actions.Implementation

  @impl true
  def run(input, [mode: mode], context)
      when mode in [:create, :create_system, :supersede, :archive, :restore] do
    run_contract_action(mode, input.arguments, context)
  end

  def run(_input, _opts, _context), do: {:error, :forbidden}

  def create(session_context, operation, %RelationshipRequest{} = request) do
    run_relationship_contract(
      :persist_create_contract,
      operation,
      request,
      session_context
    )
  end

  def create(session_context, operation, request) when is_map(request) or is_list(request) do
    with {:ok, request} <- RelationshipRequest.new(request) do
      create(session_context, operation, request)
    end
  end

  def create(_session_context, _operation, _request) do
    {:error, {:invalid_relationship_request, :request}}
  end

  def create_system(operation, %RelationshipRequest{} = request) do
    session_context = %{
      principal_id: operation.principal_id,
      organization_id: operation.organization_id,
      workspace_id: operation.workspace_id
    }

    run_relationship_contract(
      :persist_system_create_contract,
      operation,
      request,
      session_context
    )
  end

  def create_system(_operation, _request), do: {:error, :forbidden}

  def supersede(
        session_context,
        operation,
        %GraphRelationship{} = relationship,
        %RelationshipRequest{} = request
      ) do
    run_relationship_contract(
      :persist_supersede_contract,
      operation,
      request,
      session_context,
      relationship.id
    )
  end

  def supersede(_session_context, _operation, _relationship, _request) do
    {:error, {:invalid_relationship_request, :request}}
  end

  def archive(session_context, operation, %GraphRelationship{} = relationship, _attrs) do
    run_simple_relationship_contract(
      :persist_archive_contract,
      operation,
      relationship.id,
      session_context
    )
  end

  def archive(_session_context, _operation, _relationship, _attrs),
    do: {:error, :forbidden}

  def restore(session_context, operation, %GraphRelationship{} = relationship, attrs) do
    GraphRelationship
    |> Ash.ActionInput.for_action(:persist_restore_contract, %{
      operation_id: operation.id,
      relationship_id: relationship.id,
      valid_from: Map.get(Map.new(attrs || %{}), :valid_from)
    })
    |> Ash.run_action(actor: session_context, authorize?: false)
    |> normalize_contract_result()
  end

  def restore(_session_context, _operation, _relationship, _attrs),
    do: {:error, :forbidden}

  defp run_contract_action(mode, attrs, context) do
    actor = Map.get(context, :actor)

    with {:ok, operation} <- Operations.lock_operation(attrs.operation_id) do
      mode
      |> persist_contract(actor, operation, attrs)
      |> case do
        {:ok, relationship} ->
          CommandActionResult.accepted(relationship)

        {:error, error} ->
          CommandActionResult.rejected(error)
      end
    else
      {:error, error} -> CommandActionResult.rejected(error)
    end
  end

  defp persist_contract(:create, session_context, operation, attrs) do
    persist_create(session_context, operation, action_request(attrs))
  end

  defp persist_contract(:create_system, _actor, operation, attrs) do
    session_context = %{
      principal_id: operation.principal_id,
      organization_id: operation.organization_id,
      workspace_id: operation.workspace_id
    }

    persist_system_create(session_context, operation, action_request(attrs))
  end

  defp persist_contract(:supersede, session_context, operation, attrs) do
    persist_supersede(
      session_context,
      operation,
      attrs.relationship_id,
      action_request(attrs)
    )
  end

  defp persist_contract(:archive, session_context, operation, attrs) do
    persist_archive(session_context, operation, attrs.relationship_id)
  end

  defp persist_contract(:restore, session_context, operation, attrs) do
    persist_restore(session_context, operation, attrs.relationship_id, attrs.valid_from)
  end

  defp persist_create(session_context, operation, request) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- RelationshipRequest.validate(request),
         {:ok, definition} <- RelationshipDefinitions.fetch_by_key(request.definition_key),
         :ok <- RelationshipOperationPolicy.validate(operation, definition, :create),
         {:ok, endpoints} <- validate_endpoints(session_context, definition, request),
         :ok <- validate_provenance_scope(session_context, request),
         :ok <- authorize(session_context, operation, definition, endpoints, :create) do
      RelationshipCyclePolicy.lock_and_validate!(
        definition,
        session_context.organization_id,
        request
      )

      relationship =
        persist_active_relationship!(session_context, operation, definition, request, nil)

      Support.trace!(
        operation,
        "graph_relationship.create",
        "graph_relationship",
        relationship.id
      )

      {:ok, relationship}
    end
  end

  defp persist_system_create(session_context, operation, request) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         true <- is_binary(operation.workspace_id),
         :ok <- RelationshipRequest.validate(request),
         {:ok, definition} <- RelationshipDefinitions.fetch_by_key(request.definition_key),
         :ok <- RelationshipOperationPolicy.validate(operation, definition, :create),
         {:ok, endpoints} <- validate_endpoints(session_context, definition, request),
         :ok <- validate_provenance_scope(session_context, request),
         :ok <- authorize_system_cross_workspace(operation, endpoints) do
      RelationshipCyclePolicy.lock_and_validate!(
        definition,
        session_context.organization_id,
        request
      )

      relationship =
        persist_active_relationship!(session_context, operation, definition, request, nil)

      Support.trace!(
        operation,
        "graph_relationship.create",
        "graph_relationship",
        relationship.id
      )

      {:ok, relationship}
    else
      false -> {:error, :forbidden}
      error -> error
    end
  end

  defp persist_supersede(session_context, operation, relationship_id, request) do
    with :ok <- Operations.validate_operation_context(session_context, operation),
         :ok <- RelationshipRequest.validate(request) do
      locked = lock_relationship!(relationship_id)
      validate_relationship_scope(session_context, locked) |> rollback_on_error!()

      definition =
        request.definition_key
        |> RelationshipDefinitions.fetch_by_key()
        |> unwrap_or_rollback!()

      RelationshipOperationPolicy.validate(operation, definition, :supersede)
      |> rollback_on_error!()

      endpoints =
        session_context
        |> validate_endpoints(definition, request)
        |> unwrap_or_rollback!()

      existing_endpoints =
        session_context
        |> endpoints_for_relationship(locked)
        |> unwrap_or_rollback!()

      validate_provenance_scope(session_context, request) |> rollback_on_error!()

      authorize(
        session_context,
        operation,
        definition,
        endpoints,
        :supersede,
        [existing_endpoints]
      )
      |> rollback_on_error!()

      relationship =
        case locked.lifecycle do
          "active" ->
            superseded =
              locked
              |> Support.ash_update_internal(:mark_superseded, %{
                operation_id: operation.id,
                asserting_principal_id: session_context.principal_id
              })
              |> Support.unwrap_ash()

            RelationshipCyclePolicy.lock_and_validate!(
              definition,
              session_context.organization_id,
              request
            )

            replacement =
              persist_active_relationship!(
                session_context,
                operation,
                definition,
                request,
                superseded.id
              )

            Support.trace!(
              operation,
              "graph_relationship.supersede",
              "graph_relationship",
              superseded.id
            )

            Support.trace!(
              operation,
              "graph_relationship.create",
              "graph_relationship",
              replacement.id
            )

            replacement

          "superseded" ->
            replay_supersede!(locked.id, operation.id)

          lifecycle ->
            Support.rollback({:invalid_relationship_lifecycle, locked.id, lifecycle})
        end

      {:ok, relationship}
    end
  end

  defp persist_archive(session_context, operation, relationship_id) do
    with :ok <- Operations.validate_operation_context(session_context, operation) do
      locked = lock_relationship!(relationship_id)
      validate_relationship_scope(session_context, locked) |> rollback_on_error!()

      definition =
        locked.definition_id
        |> RelationshipDefinitions.fetch_by_id()
        |> unwrap_or_rollback!()

      RelationshipOperationPolicy.validate(operation, definition, :archive)
      |> rollback_on_error!()

      endpoints =
        session_context
        |> endpoints_for_relationship(locked)
        |> unwrap_or_rollback!()

      authorize(session_context, operation, definition, endpoints, :archive)
      |> rollback_on_error!()

      relationship =
        case locked.lifecycle do
          "active" ->
            archived =
              locked
              |> Support.ash_update_internal(:archive, %{
                operation_id: operation.id,
                asserting_principal_id: session_context.principal_id
              })
              |> Support.unwrap_ash()

            Support.trace!(
              operation,
              "graph_relationship.archive",
              "graph_relationship",
              archived.id
            )

            archived

          "archived" ->
            locked

          lifecycle ->
            Support.rollback({:invalid_relationship_lifecycle, locked.id, lifecycle})
        end

      {:ok, relationship}
    end
  end

  defp persist_restore(session_context, operation, relationship_id, valid_from) do
    with :ok <- Operations.validate_operation_context(session_context, operation) do
      locked = lock_relationship!(relationship_id)
      validate_relationship_scope(session_context, locked) |> rollback_on_error!()

      definition =
        locked.definition_id
        |> RelationshipDefinitions.fetch_by_id()
        |> unwrap_or_rollback!()

      RelationshipOperationPolicy.validate(operation, definition, :restore)
      |> rollback_on_error!()

      request = relationship_request(locked, %{valid_from: valid_from})

      endpoints =
        session_context
        |> validate_endpoints(definition, request)
        |> unwrap_or_rollback!()

      authorize(session_context, operation, definition, endpoints, :restore)
      |> rollback_on_error!()

      relationship =
        case locked.lifecycle do
          "archived" ->
            RelationshipCyclePolicy.lock_and_validate!(
              definition,
              session_context.organization_id,
              request
            )

            restored =
              locked
              |> Support.ash_update_internal(:restore, %{
                operation_id: operation.id,
                asserting_principal_id: session_context.principal_id,
                valid_from: request.valid_from || DateTime.utc_now()
              })
              |> Support.unwrap_ash()

            Support.trace!(
              operation,
              "graph_relationship.restore",
              "graph_relationship",
              restored.id
            )

            restored

          "active" ->
            locked

          _lifecycle ->
            Support.rollback({:relationship_restore_ineligible, locked.id})
        end

      {:ok, relationship}
    end
  end

  defp run_relationship_contract(
         action,
         operation,
         request,
         session_context,
         relationship_id \\ nil
       ) do
    GraphRelationship
    |> Ash.ActionInput.for_action(
      action,
      request
      |> relationship_action_attrs(operation.id)
      |> maybe_put_relationship_id(relationship_id)
    )
    |> Ash.run_action(actor: session_context, authorize?: false)
    |> normalize_contract_result()
  end

  defp run_simple_relationship_contract(action, operation, relationship_id, session_context) do
    GraphRelationship
    |> Ash.ActionInput.for_action(action, %{
      operation_id: operation.id,
      relationship_id: relationship_id
    })
    |> Ash.run_action(actor: session_context, authorize?: false)
    |> normalize_contract_result()
  end

  defp normalize_contract_result(result) do
    result
    |> Support.normalize_action_result()
    |> case do
      {:ok, %CommandActionResult{} = action_result} ->
        CommandActionResult.to_public_result(action_result)

      {:error, error} ->
        {:error, error}
    end
  end

  defp relationship_action_attrs(request, operation_id) do
    request
    |> Map.from_struct()
    |> Map.put(:operation_id, operation_id)
  end

  defp maybe_put_relationship_id(attrs, nil), do: attrs

  defp maybe_put_relationship_id(attrs, relationship_id),
    do: Map.put(attrs, :relationship_id, relationship_id)

  defp action_request(attrs) do
    struct!(RelationshipRequest, %{
      definition_key: attrs.definition_key,
      source_item_id: attrs.source_item_id,
      target_item_id: attrs.target_item_id,
      workspace_id: attrs.workspace_id,
      valid_from: attrs.valid_from,
      run_id: attrs.run_id,
      integration_event_id: attrs.integration_event_id
    })
  end

  defp validate_endpoints(session_context, definition, request) do
    with {:ok, source} <- Support.ash_get(GraphItem, request.source_item_id),
         {:ok, target} <- Support.ash_get(GraphItem, request.target_item_id),
         :ok <- validate_endpoint_scope(session_context, request, source, target),
         true <- compatible_endpoints?(definition, source, target) do
      {:ok, %{source: source, target: target}}
    else
      false ->
        {:error, {:invalid_relationship_endpoints, definition.key}}

      {:error, {:not_found, GraphItem, _id}} ->
        {:error, {:invalid_relationship_endpoints, definition.key}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp endpoints_for_relationship(session_context, relationship) do
    with {:ok, source} <- Support.ash_get(GraphItem, relationship.source_item_id),
         {:ok, target} <- Support.ash_get(GraphItem, relationship.target_item_id),
         :ok <-
           validate_endpoint_scope(
             session_context,
             relationship_request(relationship, %{}),
             source,
             target
           ) do
      {:ok, %{source: source, target: target}}
    end
  end

  defp validate_endpoint_scope(session_context, request, source, target) do
    governing_workspace_id = request.workspace_id || session_context.workspace_id

    cond do
      source.organization_id != session_context.organization_id ->
        {:error, :forbidden}

      target.organization_id != session_context.organization_id ->
        {:error, :forbidden}

      governing_workspace_id != session_context.workspace_id ->
        {:error, :forbidden}

      source.workspace_id != session_context.workspace_id and
          target.workspace_id != session_context.workspace_id ->
        {:error, :forbidden}

      true ->
        :ok
    end
  end

  defp compatible_endpoints?(definition, source, target) do
    Enum.any?(definition.endpoint_rules, fn rule ->
      rule.source_kind == source.resource_type and rule.target_kind == target.resource_type
    end)
  end

  defp authorize(
         session_context,
         operation,
         definition,
         endpoints,
         action,
         additional_endpoint_sets \\ []
       ) do
    authorization_action = RelationshipOperationPolicy.authorization_action(operation, action)

    with :ok <-
           Authorization.authorize_operation(
             session_context,
             operation,
             authorization_action,
             organization_id: session_context.organization_id
           ) do
      authorize_cross_workspace(
        session_context,
        operation,
        definition,
        [endpoints | additional_endpoint_sets]
      )
    end
  end

  defp authorize_cross_workspace(session_context, operation, _definition, endpoint_sets) do
    if Enum.all?(endpoint_sets, fn endpoints ->
         endpoints.source.workspace_id == session_context.workspace_id and
           endpoints.target.workspace_id == session_context.workspace_id
       end) do
      :ok
    else
      Authorization.authorize_operation(
        session_context,
        operation,
        :graph_relationship_cross_workspace,
        organization_id: session_context.organization_id
      )
    end
  end

  defp authorize_system_cross_workspace(operation, endpoints) do
    if endpoints.source.workspace_id == operation.workspace_id and
         endpoints.target.workspace_id == operation.workspace_id do
      :ok
    else
      Authorization.authorize_system_principal(
        operation.principal_id,
        operation.organization_id,
        operation.workspace_id,
        :graph_relationship_cross_workspace
      )
    end
  end

  defp persist_active_relationship!(
         session_context,
         operation,
         definition,
         request,
         supersedes_relationship_id
       ) do
    governing_workspace_id = request.workspace_id || session_context.workspace_id

    relationship =
      GraphRelationship
      |> Support.ash_create_internal(
        %{
          definition_id: definition.id,
          organization_id: session_context.organization_id,
          workspace_id: governing_workspace_id,
          source_item_id: request.source_item_id,
          target_item_id: request.target_item_id,
          asserting_principal_id: session_context.principal_id,
          operation_id: operation.id,
          valid_from: request.valid_from || DateTime.utc_now(),
          run_id: request.run_id,
          integration_event_id: request.integration_event_id,
          supersedes_relationship_id: supersedes_relationship_id
        },
        persistence_options(supersedes_relationship_id)
      )
      |> Support.unwrap_ash()

    if relationship.workspace_id == governing_workspace_id do
      relationship
    else
      Support.rollback({:relationship_governing_scope_conflict, :workspace_id})
    end
  end

  defp persistence_options(nil) do
    [
      upsert?: true,
      upsert_identity: :active_definition_edge,
      upsert_fields: []
    ]
  end

  defp persistence_options(_supersedes_relationship_id), do: []

  defp lock_relationship!(id) do
    GraphRelationship
    |> Support.ash_get_for_update(id)
    |> Support.unwrap_ash()
  end

  defp replay_supersede!(superseded_relationship_id, operation_id) do
    GraphRelationship
    |> Ash.Query.filter(
      supersedes_relationship_id == ^superseded_relationship_id and
        operation_id == ^operation_id and lifecycle == "active"
    )
    |> Support.ash_read_one_internal()
    |> case do
      {:ok, nil} ->
        Support.rollback({:relationship_supersede_replay_missing, superseded_relationship_id})

      {:ok, replacement} ->
        replacement

      {:error, error} ->
        Support.rollback(error)
    end
  end

  defp validate_relationship_scope(session_context, relationship) do
    if relationship.organization_id == session_context.organization_id and
         relationship.workspace_id == session_context.workspace_id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp validate_provenance_scope(session_context, request) do
    with :ok <- validate_provenance_reference(session_context, @run_resource, request.run_id),
         :ok <-
           validate_provenance_reference(
             session_context,
             @integration_event_resource,
             request.integration_event_id
           ) do
      :ok
    end
  end

  defp validate_provenance_reference(_session_context, _resource, nil), do: :ok

  defp validate_provenance_reference(session_context, resource, id) do
    case Support.ash_get(resource, id) do
      {:ok,
       %{
         organization_id: organization_id,
         workspace_id: workspace_id
       }}
      when organization_id == session_context.organization_id and
             workspace_id == session_context.workspace_id ->
        :ok

      _missing_or_cross_scope ->
        {:error, :forbidden}
    end
  end

  defp unwrap_or_rollback!({:ok, value}), do: value
  defp unwrap_or_rollback!({:error, error}), do: Support.rollback(error)

  defp rollback_on_error!(:ok), do: :ok
  defp rollback_on_error!({:error, error}), do: Support.rollback(error)

  defp relationship_request(relationship, attrs) do
    attrs = Map.new(attrs || %{})

    %RelationshipRequest{
      definition_key: Map.get(attrs, :definition_key, "stored_definition"),
      source_item_id: relationship.source_item_id,
      target_item_id: relationship.target_item_id,
      workspace_id: relationship.workspace_id,
      valid_from: Map.get(attrs, :valid_from),
      run_id: relationship.run_id,
      integration_event_id: relationship.integration_event_id
    }
  end
end
