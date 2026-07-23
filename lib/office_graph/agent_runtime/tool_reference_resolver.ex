defmodule OfficeGraph.AgentRuntime.ToolReferenceResolver do
  @moduledoc false

  alias OfficeGraph.Operations

  alias OfficeGraph.AgentRuntime.{
    AdapterRegistry,
    AgentExecution,
    AuthoritySnapshot,
    ContextPackage,
    ToolRequest
  }

  def dereference(
        %AgentExecution{} = execution,
        %AuthoritySnapshot{} = snapshot,
        %ContextPackage{} = context_package,
        %ToolRequest{} = request
      ) do
    with :ok <- validate_lineage(execution, snapshot, context_package, request),
         {:ok, operation} <- Operations.read_operation(request.operation_id),
         :ok <- validate_operation(operation, execution, snapshot, request.step_key),
         {:ok, adapter} <- AdapterRegistry.tool(request.tool_key, request.adapter_version),
         true <- function_exported?(adapter, :dereference, 3),
         {:ok, content} <-
           adapter.dereference(
             request.output_reference,
             request.timeout_ms,
             request.budget_units
           ),
         :ok <- validate_content(content, request) do
      {:ok,
       %{
         content: content,
         content_hash: request.output_content_hash,
         reference: request.output_reference,
         reference_id: request.id
       }}
    else
      false -> {:error, {:terminal, :tool_reference_not_dereferenceable}}
      {:error, {:not_found, _resource, _id}} -> {:error, {:terminal, :tool_reference_forbidden}}
      {:error, _reason} = error -> error
    end
  end

  def dereference(_execution, _snapshot, _context_package, _request),
    do: {:error, {:terminal, :tool_reference_forbidden}}

  defp validate_lineage(execution, snapshot, context_package, request) do
    valid? =
      request.state == "succeeded" and request.output_classification == "observation" and
        request.external_write == false and is_binary(request.output_reference) and
        is_binary(request.output_content_hash) and is_integer(request.output_byte_count) and
        request.output_byte_count > 0 and request.execution_id == execution.id and
        request.context_package_id == context_package.id and
        request.authority_snapshot_id == snapshot.id and snapshot.execution_id == execution.id and
        context_package.execution_id == execution.id and
        context_package.authority_snapshot_id == snapshot.id and
        request.tool_key in ["repository.read", "openspec.read"]

    if valid?, do: :ok, else: {:error, {:terminal, :tool_reference_forbidden}}
  end

  defp validate_operation(operation, execution, snapshot, step_key) do
    valid? =
      operation.operation_kind == "system" and
        operation.organization_id == execution.organization_id and
        operation.workspace_id == execution.workspace_id and
        operation.principal_id == execution.agent_principal_id and
        operation.action == "agent.runtime.execute" and
        operation.authority_basis == "agent-authority-snapshot:#{snapshot.id}" and
        operation.causation_key == "agent-execution:#{execution.id}" and
        operation.idempotency_scope == "agent-runtime:#{execution.id}" and
        operation.idempotency_key == "step:#{step_key}" and
        operation.subject_kind == "agent_execution" and operation.subject_id == execution.id

    if valid?, do: :ok, else: {:error, {:terminal, :tool_reference_forbidden}}
  end

  defp validate_content(content, request) when is_binary(content) do
    content_hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    if byte_size(content) == request.output_byte_count and
         content_hash == request.output_content_hash,
       do: :ok,
       else: {:error, {:terminal, :tool_reference_changed}}
  end

  defp validate_content(_content, _request),
    do: {:error, {:terminal, :tool_reference_invalid}}
end
