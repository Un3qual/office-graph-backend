defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource do
  @moduledoc false

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    id_type = Keyword.get(opts, :id_type, :uuid)

    attributes =
      for {name, type} <- Keyword.get(opts, :attributes, []) do
        quote do
          attribute unquote(name), unquote(type), allow_nil?: true, public?: false
        end
      end

    quote do
      use Ash.Resource,
        domain: OfficeGraph.TestSupport.GitHubIntegrationCleanup.Domain,
        data_layer: AshPostgres.DataLayer

      postgres do
        table unquote(table)
        repo OfficeGraph.Repo
        migrate? false
      end

      attributes do
        attribute :id, unquote(id_type),
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

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.Job do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "oban_jobs",
    id_type: :integer,
    attributes: [
      args: :map,
      worker: :string,
      queue: :string,
      meta: :map,
      attempt: :integer,
      max_attempts: :integer
    ]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.DomainEvent do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "domain_events",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.AuthorizationDecision do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "authorization_decisions",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.RawArchive do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "raw_archives",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.ExternalSource do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "external_sources",
    attributes: [key: :string, kind: :string]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.OutboundAction do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "github_outbound_actions",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.SyncOutcome do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "github_sync_outcomes",
    attributes: [installation_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.ExternalReference do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "external_references",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.Repository do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "repositories",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.PullRequest do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "pull_requests",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.ReviewThread do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "review_threads",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.ReviewComment do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "review_comments",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.CheckRun do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "check_runs",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.IntegrationCredential do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "integration_credentials",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.Installation do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "github_installations",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.InstallationCredential do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "github_installation_credentials",
    attributes: [installation_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.PermissionSnapshot do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "github_permission_snapshots",
    attributes: [installation_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.PermissionEntry do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "github_permission_entries",
    attributes: [permission_snapshot_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.Operation do
  @moduledoc false

  use OfficeGraph.TestSupport.GitHubIntegrationCleanup.Resource,
    table: "operation_correlations",
    attributes: [organization_id: :uuid]
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup.Domain do
  @moduledoc false

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.Job
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.DomainEvent
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.AuthorizationDecision
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.RawArchive
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.ExternalSource
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.OutboundAction
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.SyncOutcome
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.ExternalReference
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.Repository
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.PullRequest
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.ReviewThread
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.ReviewComment
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.CheckRun
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.IntegrationCredential
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.Installation
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.InstallationCredential
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.PermissionSnapshot
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.PermissionEntry
    resource OfficeGraph.TestSupport.GitHubIntegrationCleanup.Operation
  end
end

defmodule OfficeGraph.TestSupport.GitHubIntegrationCleanup do
  @moduledoc false

  alias __MODULE__.{
    AuthorizationDecision,
    CheckRun,
    DomainEvent,
    ExternalReference,
    ExternalSource,
    Installation,
    InstallationCredential,
    IntegrationCredential,
    Job,
    Operation,
    OutboundAction,
    PermissionEntry,
    PermissionSnapshot,
    PullRequest,
    RawArchive,
    Repository,
    ReviewComment,
    ReviewThread,
    SyncOutcome
  }

  require Ash.Query

  def cleanup_scope!(organization_id) do
    installation_ids =
      Installation
      |> Ash.Query.filter(organization_id == ^organization_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    destroy_jobs!(organization_id)
    destroy_for_organization!(DomainEvent, organization_id)
    destroy_for_organization!(OutboundAction, organization_id)
    destroy_for_installations!(SyncOutcome, installation_ids)

    OfficeGraph.TestSupport.ConcurrencySupport.cleanup_work_run_verification_scope_by_id!(
      organization_id
    )

    destroy_for_organization!(ExternalReference, organization_id)
    destroy_for_organization!(CheckRun, organization_id)
    destroy_for_organization!(ReviewComment, organization_id)
    destroy_for_organization!(ReviewThread, organization_id)
    destroy_for_organization!(PullRequest, organization_id)
    destroy_for_organization!(Repository, organization_id)
    destroy_for_organization!(RawArchive, organization_id)

    snapshot_ids =
      PermissionSnapshot
      |> Ash.Query.filter(installation_id in ^installation_ids)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    destroy_for_snapshots!(PermissionEntry, snapshot_ids)
    destroy_for_installations!(InstallationCredential, installation_ids)
    destroy_for_organization!(Installation, organization_id)
    destroy_for_installations!(PermissionSnapshot, installation_ids)
    destroy_for_organization!(IntegrationCredential, organization_id)
    destroy_for_organization!(AuthorizationDecision, organization_id)
    destroy_for_organization!(Operation, organization_id)
    destroy_provider_sources!()

    :ok
  end

  def jobs_for_action(action_id) do
    Job
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(Map.get(&1.args || %{}, "action_id") == action_id))
  end

  def jobs_for_delivery(delivery_id) do
    Job
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(Map.get(&1.args || %{}, "delivery_id") == delivery_id))
  end

  def oban_job_for_action!(action_id) do
    [job] = jobs_for_action(action_id)
    to_oban_job(job)
  end

  def oban_job_for_delivery!(delivery_id, worker) do
    [job] =
      delivery_id
      |> jobs_for_delivery()
      |> Enum.filter(&(&1.worker == worker))

    to_oban_job(job)
  end

  defp to_oban_job(job) do
    job
    |> Map.from_struct()
    |> Map.take([:id, :args, :worker, :queue, :meta, :attempt, :max_attempts])
    |> then(&struct!(Oban.Job, &1))
  end

  defp destroy_jobs!(organization_id) do
    Job
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(Map.get(&1.args || %{}, "organization_id") == organization_id))
    |> Enum.each(&Ash.destroy!(&1, authorize?: false))
  end

  defp destroy_for_organization!(resource, organization_id) do
    resource
    |> Ash.Query.filter(organization_id == ^organization_id)
    |> destroy_all!()
  end

  defp destroy_for_installations!(_resource, []), do: :ok

  defp destroy_for_installations!(resource, installation_ids) do
    resource
    |> Ash.Query.filter(installation_id in ^installation_ids)
    |> destroy_all!()
  end

  defp destroy_for_snapshots!(_resource, []), do: :ok

  defp destroy_for_snapshots!(resource, snapshot_ids) do
    resource
    |> Ash.Query.filter(permission_snapshot_id in ^snapshot_ids)
    |> destroy_all!()
  end

  defp destroy_provider_sources! do
    ExternalSource
    |> Ash.Query.filter(kind == "provider" and key in ["github", "github_app:office-graph"])
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
