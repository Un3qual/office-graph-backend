defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource do
  @moduledoc false

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)

    attributes =
      for {name, type} <- Keyword.get(opts, :attributes, []) do
        quote do
          attribute unquote(name), unquote(type), allow_nil?: true, public?: false
        end
      end

    quote do
      use Ash.Resource,
        domain: OfficeGraph.TestSupport.AgentRuntimeCleanup.Domain,
        data_layer: AshPostgres.DataLayer

      postgres do
        table unquote(table)
        repo OfficeGraph.Repo
        migrate? false
      end

      attributes do
        attribute :id, :uuid,
          primary_key?: true,
          allow_nil?: false,
          public?: false

        unquote_splicing(attributes)
      end

      actions do
        read :read do
          primary? true
          public? false
        end

        destroy :destroy do
          primary? true
          public? false
        end
      end
    end
  end
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.Execution do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_executions",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.Binding do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_organization_bindings",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.Approval do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_approval_requests",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.ContextExpansion do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_context_expansion_requests",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.ContextPackage do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_context_packages",
    attributes: [
      organization_id: :uuid,
      expansion_request_id: :uuid,
      version: :integer
    ]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.ContextEntry do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_context_entries",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.AuthoritySnapshot do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_authority_snapshots",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.ModelRequest do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_model_requests",
    attributes: [execution_id: :uuid]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.ToolRequest do
  @moduledoc false

  use OfficeGraph.TestSupport.AgentRuntimeCleanup.Resource,
    table: "agent_tool_requests",
    attributes: [execution_id: :uuid]
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.Execution
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.Binding
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.Approval
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.ContextExpansion
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.ContextPackage
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.ContextEntry
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.AuthoritySnapshot
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.ModelRequest
    resource OfficeGraph.TestSupport.AgentRuntimeCleanup.ToolRequest
  end
end

defmodule OfficeGraph.TestSupport.AgentRuntimeCleanup do
  @moduledoc false

  alias __MODULE__.{
    Approval,
    AuthoritySnapshot,
    Binding,
    ContextEntry,
    ContextExpansion,
    ContextPackage,
    Execution,
    ModelRequest,
    ToolRequest
  }

  require Ash.Query

  def cleanup_scope!(organization_id) do
    execution_ids =
      Execution
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    destroy_for_executions!(ModelRequest, execution_ids)
    destroy_for_executions!(ToolRequest, execution_ids)
    destroy_for_organization!(Approval, organization_id)
    destroy_for_organization!(ContextEntry, organization_id)

    ContextPackage
    |> Ash.Query.filter(organization_id == ^organization_id and not is_nil(expansion_request_id))
    |> destroy_all!()

    destroy_for_organization!(ContextExpansion, organization_id)
    destroy_for_organization!(ContextPackage, organization_id)
    destroy_for_organization!(AuthoritySnapshot, organization_id)
    destroy_for_organization!(Execution, organization_id)
    destroy_for_organization!(Binding, organization_id)

    :ok
  end

  defp destroy_for_executions!(_resource, []), do: :ok

  defp destroy_for_executions!(resource, execution_ids) do
    resource
    |> Ash.Query.filter(execution_id in ^execution_ids)
    |> destroy_all!()
  end

  defp destroy_for_organization!(resource, organization_id) do
    resource
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> destroy_all!()
  end

  defp destroy_all!(query) do
    Ash.bulk_destroy!(query, :destroy, %{},
      authorize?: false,
      return_errors?: true,
      strategy: [:atomic]
    )

    :ok
  end
end
