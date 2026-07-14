defmodule OfficeGraph.GitHubIntegration.Reconciler do
  @moduledoc false

  alias OfficeGraph.{
    DurableDelivery,
    ExternalRefs,
    Integrations,
    Operations,
    Repo,
    SoftwareProving,
    WorkGraph
  }

  alias OfficeGraph.GitHubIntegration.{
    Adapter,
    Installation,
    InstallationCredential,
    ReconciliationRequest,
    SecretStore,
    SyncOutcome
  }

  alias OfficeGraph.SoftwareProving.{
    CheckRun,
    PullRequest,
    Repository,
    ReviewComment,
    ReviewThread
  }

  alias OfficeGraph.SoftwareProving.GitHub.{
    CheckRunExtension,
    PullRequestExtension,
    RepositoryExtension,
    ReviewCommentExtension,
    ReviewThreadExtension
  }

  require Ash.Query

  def reconcile(operation, %ReconciliationRequest{} = request) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         {:ok, nil} <- outcome_by_operation(operation.id),
         {:ok, installation} <- authorized_installation(operation, request),
         {:ok, credential} <- resolve_credential(operation, installation),
         {:ok, source} <- Integrations.ensure_provider_source("github", "GitHub"),
         {:ok, snapshot} <- fetch_snapshot(request, installation, credential) do
      reconcile_snapshot(operation, request, installation, source, snapshot)
    else
      {:ok, %SyncOutcome{} = outcome} -> replay_outcome(outcome, request)
      {:error, {:provider, reason}} -> record_failure(operation, request, reason)
      {:error, _error} = error -> error
    end
  end

  def reconcile(_operation, _request), do: {:error, :forbidden}

  defp authorized_installation(operation, request) do
    case Ash.get(Installation, request.installation_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %Installation{
         lifecycle_state: "active",
         organization_id: organization_id,
         workspace_id: workspace_id,
         service_principal_id: principal_id
       } = installation}
      when organization_id == operation.organization_id and
             workspace_id == operation.workspace_id and
             principal_id == operation.principal_id ->
        if operation.authority_basis == "github_installation:#{installation.id}",
          do: {:ok, installation},
          else: {:error, :forbidden}

      _missing_or_cross_scope ->
        {:error, :forbidden}
    end
  end

  defp resolve_credential(operation, installation) do
    InstallationCredential
    |> Ash.Query.filter(
      installation_id == ^installation.id and purpose == "app_private_key" and
        credential_id == ^operation.credential_id
    )
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, %InstallationCredential{credential_id: credential_id}} ->
        SecretStore.resolve(credential_id, %{
          organization_id: installation.organization_id,
          workspace_id: installation.workspace_id
        })

      _missing_or_invalid ->
        {:error, :forbidden}
    end
  end

  defp fetch_snapshot(request, installation, credential) do
    adapter = Application.fetch_env!(:office_graph, :github_adapter)

    request
    |> Map.put(:external_installation_id, installation.external_installation_id)
    |> Map.put(:credential, credential)
    |> adapter.fetch()
    |> case do
      {:ok, %Adapter.ReconciliationSnapshot{} = snapshot} -> validate_snapshot(snapshot, request)
      {:ok, _invalid} -> {:error, {:provider, :invalid_provider_response}}
      {:error, reason} -> {:error, {:provider, reason}}
    end
  end

  defp validate_snapshot(snapshot, request) do
    valid? =
      is_binary(snapshot.provider_version) and snapshot.provider_version != "" and
        is_integer(snapshot.provider_sequence) and snapshot.provider_sequence >= 0 and
        match?(%Adapter.RepositorySnapshot{}, snapshot.repository) and
        match?(%Adapter.PullRequestSnapshot{}, snapshot.pull_request) and
        matching_root_object?(snapshot, request) and
        Enum.all?(snapshot.review_threads, &match?(%Adapter.ReviewThreadSnapshot{}, &1)) and
        Enum.all?(snapshot.review_comments, &match?(%Adapter.ReviewCommentSnapshot{}, &1)) and
        Enum.all?(snapshot.check_runs, &match?(%Adapter.CheckRunSnapshot{}, &1))

    if valid?, do: {:ok, snapshot}, else: {:error, {:provider, :invalid_provider_response}}
  end

  defp matching_root_object?(snapshot, %{object_type: "pull_request", object_id: object_id}),
    do: snapshot.pull_request.node_id == object_id

  defp matching_root_object?(_snapshot, _request), do: true

  defp reconcile_snapshot(operation, request, installation, source, snapshot) do
    case Repo.transaction(fn ->
           lock!("github:#{installation.id}:#{request.object_type}:#{request.object_id}")

           case outcome_by_operation(operation.id) do
             {:ok, nil} -> persist_snapshot!(operation, request, installation, source, snapshot)
             {:ok, outcome} -> outcome
             {:error, error} -> Repo.rollback(error)
           end
         end) do
      {:ok, outcome} -> replay_outcome(outcome, request)
      {:error, error} -> {:error, error}
    end
  end

  defp persist_snapshot!(operation, request, installation, source, snapshot) do
    repository = reconcile_repository!(operation, source, snapshot)
    pull_request = reconcile_pull_request!(operation, source, repository, snapshot)

    if pull_request.status == :stale do
      create_outcome!(
        operation,
        request,
        installation,
        snapshot,
        pull_request.record,
        [],
        "skipped_stale"
      )
    else
      thread_ids = reconcile_threads!(operation, source, pull_request.record, snapshot)
      comments = reconcile_comments!(operation, source, pull_request.record, thread_ids, snapshot)

      checks =
        reconcile_checks!(operation, source, repository.record, pull_request.record, snapshot)

      signal_ids = map_product_work!(operation, source, comments, checks)
      record_invalidation!(operation, pull_request.record, snapshot)

      create_outcome!(
        operation,
        request,
        installation,
        snapshot,
        pull_request.record,
        signal_ids,
        "reconciled"
      )
    end
  end

  defp reconcile_repository!(operation, source, snapshot) do
    lock!("github:repository:#{snapshot.repository.node_id}")

    existing =
      base_by_extension(
        RepositoryExtension,
        :repository_id,
        Repository,
        snapshot.repository.node_id
      )

    result =
      SoftwareProving.upsert_provider_resource(operation, source, Repository, existing, %{
        name: snapshot.repository.name,
        full_name: snapshot.repository.full_name,
        default_ref_name: snapshot.repository.default_ref_name,
        visibility: snapshot.repository.visibility,
        provider_version: snapshot.provider_version,
        provider_sequence: snapshot.provider_sequence,
        provider_updated_at: snapshot.provider_updated_at
      })
      |> unwrap!()

    ensure_extension!(RepositoryExtension, :repository_id, result.record.id, %{
      node_id: snapshot.repository.node_id,
      database_id: snapshot.repository.database_id,
      owner_login: snapshot.repository.owner_login
    })

    maybe_reference!(
      operation,
      source,
      result.record,
      "repository",
      snapshot.repository.node_id,
      snapshot.repository.url
    )

    result
  end

  defp reconcile_pull_request!(operation, source, repository, snapshot) do
    existing =
      base_by_extension(
        PullRequestExtension,
        :pull_request_id,
        PullRequest,
        snapshot.pull_request.node_id
      )

    result =
      SoftwareProving.upsert_provider_resource(operation, source, PullRequest, existing, %{
        repository_id: repository.record.id,
        number: snapshot.pull_request.number,
        title: snapshot.pull_request.title,
        body: snapshot.pull_request.body,
        state: snapshot.pull_request.state,
        is_draft: snapshot.pull_request.is_draft,
        author_label: snapshot.pull_request.author_label,
        opened_at: snapshot.pull_request.opened_at,
        closed_at: snapshot.pull_request.closed_at,
        merged_at: snapshot.pull_request.merged_at,
        provider_version: snapshot.provider_version,
        provider_sequence: snapshot.provider_sequence,
        provider_updated_at: snapshot.provider_updated_at
      })
      |> unwrap!()

    ensure_extension!(PullRequestExtension, :pull_request_id, result.record.id, %{
      node_id: snapshot.pull_request.node_id,
      database_id: snapshot.pull_request.database_id
    })

    maybe_reference!(
      operation,
      source,
      result.record,
      "pull_request",
      snapshot.pull_request.node_id,
      snapshot.pull_request.url
    )

    result
  end

  defp reconcile_threads!(operation, source, pull_request, snapshot) do
    Map.new(snapshot.review_threads, fn thread ->
      existing =
        base_by_extension(ReviewThreadExtension, :review_thread_id, ReviewThread, thread.node_id)

      result =
        SoftwareProving.upsert_provider_resource(operation, source, ReviewThread, existing, %{
          pull_request_id: pull_request.id,
          state: thread.state,
          path: thread.path,
          line: thread.line,
          side: thread.side,
          resolved_at: thread.resolved_at,
          provider_version: snapshot.provider_version,
          provider_sequence: snapshot.provider_sequence,
          provider_updated_at: snapshot.provider_updated_at
        })
        |> unwrap!()

      ensure_extension!(ReviewThreadExtension, :review_thread_id, result.record.id, %{
        node_id: thread.node_id
      })

      {thread.node_id, result.record.id}
    end)
  end

  defp reconcile_comments!(operation, source, pull_request, thread_ids, snapshot) do
    Enum.map(snapshot.review_comments, fn comment ->
      existing =
        base_by_extension(
          ReviewCommentExtension,
          :review_comment_id,
          ReviewComment,
          comment.node_id
        )

      result =
        SoftwareProving.upsert_provider_resource(operation, source, ReviewComment, existing, %{
          pull_request_id: pull_request.id,
          review_thread_id: Map.get(thread_ids, comment.review_thread_node_id),
          body: comment.body,
          author_label: comment.author_label,
          state: comment.state,
          published_at: comment.published_at,
          provider_version: snapshot.provider_version,
          provider_sequence: snapshot.provider_sequence,
          provider_updated_at: snapshot.provider_updated_at
        })
        |> unwrap!()

      ensure_extension!(ReviewCommentExtension, :review_comment_id, result.record.id, %{
        node_id: comment.node_id,
        database_id: comment.database_id,
        review_database_id: comment.review_database_id
      })

      reference =
        maybe_reference!(
          operation,
          source,
          result.record,
          "review_comment",
          comment.node_id,
          comment.url
        )

      %{record: result.record, snapshot: comment, reference: reference}
    end)
  end

  defp reconcile_checks!(operation, source, repository, pull_request, snapshot) do
    Enum.map(snapshot.check_runs, fn check ->
      existing = base_by_extension(CheckRunExtension, :check_run_id, CheckRun, check.node_id)

      result =
        SoftwareProving.upsert_provider_resource(operation, source, CheckRun, existing, %{
          repository_id: repository.id,
          pull_request_id: pull_request.id,
          name: check.name,
          status: check.status,
          conclusion: check.conclusion,
          details_url: check.details_url,
          started_at: check.started_at,
          completed_at: check.completed_at,
          provider_version: snapshot.provider_version,
          provider_sequence: snapshot.provider_sequence,
          provider_updated_at: snapshot.provider_updated_at
        })
        |> unwrap!()

      ensure_extension!(CheckRunExtension, :check_run_id, result.record.id, %{
        node_id: check.node_id,
        database_id: check.database_id,
        check_suite_database_id: check.check_suite_database_id
      })

      reference =
        maybe_reference!(
          operation,
          source,
          result.record,
          "check_run",
          check.node_id,
          check.details_url
        )

      %{record: result.record, snapshot: check, reference: reference}
    end)
  end

  defp map_product_work!(operation, _source, comments, checks) do
    comment_signals =
      Enum.map(comments, fn item ->
        WorkGraph.ensure_integration_signal(operation, item.reference, %{
          title: "Review comment from #{item.record.author_label || "GitHub"}",
          body: item.record.body
        })
        |> unwrap!()
        |> Map.fetch!(:signal)
        |> Map.fetch!(:id)
      end)

    check_signals =
      checks
      |> Enum.filter(&failing_check?(&1.record))
      |> Enum.map(fn item ->
        WorkGraph.ensure_integration_signal(operation, item.reference, %{
          title: "Failing check: #{item.record.name}",
          body: "#{item.record.name} concluded with #{item.record.conclusion}."
        })
        |> unwrap!()
        |> Map.fetch!(:signal)
        |> Map.fetch!(:id)
      end)

    comment_signals ++ check_signals
  end

  defp failing_check?(%{status: "completed", conclusion: conclusion}),
    do: conclusion in ~w(failure timed_out cancelled action_required startup_failure)

  defp failing_check?(_check), do: false

  defp maybe_reference!(operation, source, record, object_type, node_id, url) do
    ExternalRefs.upsert_provider_reference(operation, source, %{
      provider: "github",
      object_type: object_type,
      external_id: "#{object_type}:#{node_id}",
      url: url,
      resource_type: resource_type(record),
      resource_id: record.id
    })
    |> unwrap!()
  end

  defp base_by_extension(extension, base_key, base_resource, node_id) do
    extension
    |> Ash.Query.filter(node_id == ^node_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} -> nil
      {:ok, record} -> Ash.get!(base_resource, Map.fetch!(record, base_key), authorize?: false)
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp ensure_extension!(extension, base_key, base_id, attrs) do
    extension
    |> Ash.Query.filter(node_id == ^attrs.node_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        Repo.ash_create!(extension, Map.put(attrs, base_key, base_id))

      {:ok, existing} ->
        if Map.fetch!(existing, base_key) == base_id,
          do: existing,
          else: Repo.rollback(:provider_identity_conflict)

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp create_outcome!(operation, request, installation, snapshot, resource, signal_ids, state) do
    Repo.ash_create!(SyncOutcome, %{
      id: Ecto.UUID.generate(),
      installation_id: installation.id,
      operation_id: operation.id,
      object_type: request.object_type,
      object_id: request.object_id,
      delivery_id: request.delivery_id,
      state: state,
      provider_version: snapshot.provider_version,
      provider_sequence: snapshot.provider_sequence,
      resource_type: resource_type(resource),
      resource_id: resource.id,
      signal_ids: signal_ids
    })
  end

  defp record_invalidation!(operation, pull_request, snapshot) do
    DurableDelivery.record_system_and_enqueue(operation, %{
      event_key: "github-reconciliation:#{operation.id}",
      event_kind: "github.reconciliation.completed",
      subject_kind: "pull_request",
      subject_id: pull_request.id,
      subject_version: if(snapshot.provider_sequence > 0, do: snapshot.provider_sequence)
    })
    |> unwrap!()
  end

  defp record_failure(operation, request, reason) do
    {failure_class, failure_code} = classify_failure(reason)

    case authorized_installation(operation, request) do
      {:ok, installation} ->
        outcome =
          Repo.ash_create!(SyncOutcome, %{
            id: Ecto.UUID.generate(),
            installation_id: installation.id,
            operation_id: operation.id,
            object_type: request.object_type,
            object_id: request.object_id,
            delivery_id: request.delivery_id,
            state: Atom.to_string(failure_class),
            signal_ids: [],
            failure_class: Atom.to_string(failure_class),
            failure_code: Atom.to_string(failure_code)
          })

        replay_outcome(outcome, request)

      {:error, _error} ->
        {:error, {failure_class, failure_code}}
    end
  end

  defp classify_failure({:rate_limited, %DateTime{}}), do: {:retryable, :provider_rate_limited}
  defp classify_failure(:installation_revoked), do: {:terminal, :installation_revoked}
  defp classify_failure(:invalid_credential), do: {:terminal, :invalid_credential}
  defp classify_failure(:adapter_unavailable), do: {:configuration, :adapter_unavailable}
  defp classify_failure(:fixture_not_found), do: {:terminal, :provider_object_not_found}
  defp classify_failure(_reason), do: {:terminal, :invalid_provider_response}

  defp replay_outcome(outcome, request) do
    if outcome.object_type == request.object_type and outcome.object_id == request.object_id and
         outcome.delivery_id == request.delivery_id do
      case outcome.state do
        state when state in ~w(reconciled skipped_stale) -> {:ok, outcome}
        "retryable" -> {:error, {:retryable, known_code(outcome.failure_code)}}
        "terminal" -> {:error, {:terminal, known_code(outcome.failure_code)}}
        "authorization" -> {:error, {:authorization, known_code(outcome.failure_code)}}
        "configuration" -> {:error, {:configuration, known_code(outcome.failure_code)}}
      end
    else
      {:error, :forbidden}
    end
  end

  defp known_code("provider_rate_limited"), do: :provider_rate_limited
  defp known_code("installation_revoked"), do: :installation_revoked
  defp known_code("invalid_credential"), do: :invalid_credential
  defp known_code("adapter_unavailable"), do: :adapter_unavailable
  defp known_code("provider_object_not_found"), do: :provider_object_not_found
  defp known_code(_code), do: :invalid_provider_response

  defp outcome_by_operation(operation_id) do
    SyncOutcome
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.read_one(authorize?: false)
  end

  defp lock!(key), do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

  defp resource_type(record),
    do: record.__struct__ |> Module.split() |> List.last() |> Macro.underscore()

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: Repo.rollback(error)
end
