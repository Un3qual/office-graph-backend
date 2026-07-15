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

  @repository_visibilities ~w(public internal private)
  @pull_request_states ~w(open closed merged)
  @review_thread_states ~w(open resolved outdated)
  @review_comment_states ~w(pending published minimized deleted)
  @check_statuses ~w(queued in_progress completed)
  @check_conclusions ~w(success failure neutral cancelled skipped timed_out action_required startup_failure stale)
  @retryable_failure_codes [:provider_rate_limited, :provider_unavailable]

  require Ash.Query

  def reconcile(operation, %ReconciliationRequest{} = request) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         {:ok, outcome} <- outcome_by_operation(operation.id) do
      continue_or_replay(operation, request, outcome)
    end
  end

  def reconcile(_operation, _request), do: {:error, :forbidden}

  def exhaust_retry(operation, %ReconciliationRequest{} = request, failure_code) do
    if failure_code in @retryable_failure_codes do
      with :ok <- Operations.validate_system_operation(operation, :integration_reconcile) do
        Repo.transaction(fn ->
          lock!("github:sync-outcome:#{operation.id}")
          terminalize_retry!(operation.id, request, failure_code)
        end)
      end
    else
      {:error, :forbidden}
    end
  end

  def exhaust_retry(_operation, _request, _failure_code), do: {:error, :forbidden}

  defp continue_or_replay(operation, request, nil),
    do: reconcile_provider(operation, request)

  defp continue_or_replay(operation, request, %SyncOutcome{state: "retryable"} = outcome) do
    case replay_outcome(outcome, request) do
      {:error, {:retryable, _code}} -> reconcile_provider(operation, request)
      {:error, {:retryable, _code, %DateTime{}}} -> reconcile_provider(operation, request)
      error -> error
    end
  end

  defp continue_or_replay(_operation, request, %SyncOutcome{} = outcome),
    do: replay_outcome(outcome, request)

  defp reconcile_provider(operation, request) do
    with {:ok, installation} <- authorized_installation(operation, request),
         {:ok, credential} <- resolve_credential(operation, installation),
         {:ok, source} <- Integrations.ensure_provider_source("github", "GitHub"),
         {:ok, snapshot} <- fetch_snapshot(request, installation, credential) do
      reconcile_snapshot(operation, request, installation, source, snapshot)
    else
      {:error, {:provider, reason}} -> record_failure(operation, request, reason)
      {:error, _error} = error -> error
    end
  end

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
        credential_id
        |> SecretStore.resolve(%{
          organization_id: installation.organization_id,
          workspace_id: installation.workspace_id
        })
        |> classify_credential_resolution()

      _missing_or_invalid ->
        {:error, :forbidden}
    end
  end

  defp classify_credential_resolution({:ok, credential}), do: {:ok, credential}

  defp classify_credential_resolution({:error, :unavailable}),
    do: {:error, {:provider, :provider_unavailable}}

  defp classify_credential_resolution({:error, reason})
       when reason in [:forbidden, :invalid_secret_reference, :secret_not_found],
       do: {:error, {:provider, :invalid_credential}}

  defp fetch_snapshot(request, installation, credential) do
    adapter = Application.fetch_env!(:office_graph, :github_adapter)

    request
    |> Map.put(:external_installation_id, installation.external_installation_id)
    |> Map.put(:credential, credential)
    |> adapter.fetch()
    |> case do
      {:ok, %Adapter.ReconciliationSnapshot{} = snapshot} ->
        snapshot
        |> normalize_snapshot()
        |> validate_snapshot(request)

      {:ok, _invalid} ->
        {:error, {:provider, :invalid_provider_response}}

      {:error, reason} ->
        {:error, {:provider, reason}}
    end
  end

  defp normalize_snapshot(%Adapter.ReconciliationSnapshot{check_runs: check_runs} = snapshot)
       when is_list(check_runs) do
    %{snapshot | check_runs: Enum.map(check_runs, &normalize_check_run/1)}
  end

  defp normalize_snapshot(snapshot), do: snapshot

  defp normalize_check_run(%Adapter.CheckRunSnapshot{status: status} = check)
       when status in ~w(requested waiting pending),
       do: %{check | status: "queued"}

  defp normalize_check_run(check), do: check

  defp validate_snapshot(snapshot, request) do
    valid? =
      nonblank_string?(snapshot.provider_version) and
        is_integer(snapshot.provider_sequence) and snapshot.provider_sequence >= 0 and
        optional_datetime?(snapshot.provider_updated_at) and
        valid_repository?(snapshot.repository) and
        valid_pull_request?(snapshot.pull_request) and
        valid_collection?(snapshot.review_threads, &valid_review_thread?/1) and
        valid_collection?(snapshot.review_comments, &valid_review_comment?/1) and
        valid_collection?(snapshot.check_runs, &valid_check_run?/1) and
        matching_root_object?(snapshot, request) and
        unique_node_ids?(snapshot.review_threads) and
        unique_node_ids?(snapshot.review_comments) and
        unique_node_ids?(snapshot.check_runs) and
        valid_comment_parents?(snapshot.review_comments) and
        valid_comment_threads?(snapshot.review_comments, snapshot.review_threads)

    if valid?, do: {:ok, snapshot}, else: {:error, {:provider, :invalid_provider_response}}
  end

  defp matching_root_object?(snapshot, %{object_type: "pull_request", object_id: object_id}),
    do: provider_object_matches?(snapshot.pull_request, object_id)

  defp matching_root_object?(snapshot, %{object_type: "review_comment", object_id: object_id}),
    do: Enum.any?(snapshot.review_comments, &provider_object_matches?(&1, object_id))

  defp matching_root_object?(snapshot, %{object_type: "check_run", object_id: object_id}),
    do: Enum.any?(snapshot.check_runs, &provider_object_matches?(&1, object_id))

  defp matching_root_object?(_snapshot, _request), do: false

  defp provider_object_matches?(object, object_id) do
    object.node_id == object_id or
      (is_integer(object.database_id) and Integer.to_string(object.database_id) == object_id)
  end

  defp valid_repository?(%Adapter.RepositorySnapshot{} = repository) do
    nonblank_string?(repository.node_id) and optional_positive_integer?(repository.database_id) and
      nonblank_string?(repository.name) and nonblank_string?(repository.full_name) and
      nonblank_string?(repository.owner_login) and optional_string?(repository.default_ref_name) and
      repository.visibility in @repository_visibilities and optional_string?(repository.url)
  end

  defp valid_repository?(_repository), do: false

  defp valid_pull_request?(%Adapter.PullRequestSnapshot{} = pull_request) do
    nonblank_string?(pull_request.node_id) and
      optional_positive_integer?(pull_request.database_id) and
      is_integer(pull_request.number) and pull_request.number > 0 and
      nonblank_string?(pull_request.title) and optional_string?(pull_request.body) and
      pull_request.state in @pull_request_states and is_boolean(pull_request.is_draft) and
      optional_string?(pull_request.author_label) and optional_string?(pull_request.url) and
      optional_datetime?(pull_request.opened_at) and optional_datetime?(pull_request.closed_at) and
      optional_datetime?(pull_request.merged_at)
  end

  defp valid_pull_request?(_pull_request), do: false

  defp valid_review_thread?(%Adapter.ReviewThreadSnapshot{} = thread) do
    nonblank_string?(thread.node_id) and thread.state in @review_thread_states and
      optional_string?(thread.path) and optional_positive_integer?(thread.line) and
      (is_nil(thread.side) or thread.side in ~w(LEFT RIGHT)) and
      optional_datetime?(thread.resolved_at)
  end

  defp valid_review_thread?(_thread), do: false

  defp valid_review_comment?(%Adapter.ReviewCommentSnapshot{} = comment) do
    nonblank_string?(comment.node_id) and optional_positive_integer?(comment.database_id) and
      optional_positive_integer?(comment.review_database_id) and
      optional_string?(comment.review_thread_node_id) and
      optional_string?(comment.parent_comment_node_id) and valid_review_comment_body?(comment) and
      optional_string?(comment.author_label) and comment.state in @review_comment_states and
      optional_datetime?(comment.published_at) and optional_string?(comment.url)
  end

  defp valid_review_comment?(_comment), do: false

  defp valid_review_comment_body?(%{state: "published", body: body}),
    do: nonblank_string?(body)

  defp valid_review_comment_body?(%{body: body}), do: is_binary(body)

  defp valid_check_run?(%Adapter.CheckRunSnapshot{} = check) do
    nonblank_string?(check.node_id) and optional_positive_integer?(check.database_id) and
      optional_positive_integer?(check.check_suite_database_id) and nonblank_string?(check.name) and
      check.status in @check_statuses and valid_check_state?(check) and
      optional_string?(check.details_url) and optional_datetime?(check.started_at) and
      optional_datetime?(check.completed_at)
  end

  defp valid_check_run?(_check), do: false

  defp valid_check_state?(%{status: "completed", conclusion: conclusion}),
    do: conclusion in @check_conclusions

  defp valid_check_state?(%{status: status, conclusion: nil})
       when status in ~w(queued in_progress),
       do: true

  defp valid_check_state?(_check), do: false

  defp valid_collection?(items, validator) when is_list(items), do: Enum.all?(items, validator)
  defp valid_collection?(_items, _validator), do: false

  defp unique_node_ids?(items) when is_list(items) do
    ids = Enum.map(items, & &1.node_id)
    Enum.uniq(ids) == ids
  end

  defp valid_comment_parents?(comments) when is_list(comments) do
    node_ids = MapSet.new(comments, & &1.node_id)

    Enum.all?(comments, fn comment ->
      is_nil(comment.parent_comment_node_id) or
        (comment.parent_comment_node_id != comment.node_id and
           MapSet.member?(node_ids, comment.parent_comment_node_id))
    end)
  end

  defp valid_comment_threads?(comments, threads) when is_list(comments) and is_list(threads) do
    thread_node_ids = MapSet.new(threads, & &1.node_id)

    Enum.all?(comments, fn comment ->
      is_nil(comment.review_thread_node_id) or
        MapSet.member?(thread_node_ids, comment.review_thread_node_id)
    end)
  end

  defp nonblank_string?(value), do: is_binary(value) and String.trim(value) != ""
  defp optional_string?(value), do: is_nil(value) or is_binary(value)
  defp optional_datetime?(value), do: is_nil(value) or match?(%DateTime{}, value)

  defp optional_positive_integer?(value),
    do: is_nil(value) or (is_integer(value) and value > 0)

  defp reconcile_snapshot(operation, request, installation, source, snapshot) do
    case Repo.transaction(fn ->
           lock!("github:sync-outcome:#{operation.id}")
           lock!("github:#{installation.id}:#{request.object_type}:#{request.object_id}")

           case outcome_by_operation(operation.id) do
             {:ok, nil} ->
               persist_snapshot!(operation, request, installation, source, snapshot)

             {:ok, %SyncOutcome{state: "retryable"}} ->
               persist_snapshot!(operation, request, installation, source, snapshot)

             {:ok, outcome} ->
               outcome

             {:error, error} ->
               Repo.rollback(error)
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

      signal_ids =
        map_product_work!(operation, comments, checks, snapshot.review_threads)

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
    lock!(
      "github:repository:#{operation.organization_id}:#{operation.workspace_id || "organization"}:#{snapshot.repository.node_id}"
    )

    existing =
      base_by_extension(
        operation,
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

    ensure_extension!(
      operation,
      RepositoryExtension,
      :repository_id,
      result.record.id,
      %{
        node_id: snapshot.repository.node_id,
        database_id: snapshot.repository.database_id,
        owner_login: snapshot.repository.owner_login
      }
    )

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
        operation,
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

    ensure_extension!(
      operation,
      PullRequestExtension,
      :pull_request_id,
      result.record.id,
      %{
        node_id: snapshot.pull_request.node_id,
        database_id: snapshot.pull_request.database_id
      }
    )

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
        base_by_extension(
          operation,
          ReviewThreadExtension,
          :review_thread_id,
          ReviewThread,
          thread.node_id
        )

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

      ensure_extension!(
        operation,
        ReviewThreadExtension,
        :review_thread_id,
        result.record.id,
        %{node_id: thread.node_id}
      )

      {thread.node_id, result.record.id}
    end)
  end

  defp reconcile_comments!(operation, source, pull_request, thread_ids, snapshot) do
    reconcile_comment_batch!(
      snapshot.review_comments,
      operation,
      source,
      pull_request,
      thread_ids,
      snapshot,
      %{},
      []
    )
  end

  defp reconcile_comment_batch!(
         [],
         _operation,
         _source,
         _pull_request,
         _thread_ids,
         _snapshot,
         _comment_ids,
         reconciled
       ),
       do: Enum.reverse(reconciled)

  defp reconcile_comment_batch!(
         pending,
         operation,
         source,
         pull_request,
         thread_ids,
         snapshot,
         comment_ids,
         reconciled
       ) do
    {ready, blocked} =
      Enum.split_with(pending, fn comment ->
        is_nil(comment.parent_comment_node_id) or
          Map.has_key?(comment_ids, comment.parent_comment_node_id)
      end)

    if ready == [] do
      Repo.rollback(:invalid_provider_response)
    else
      {comment_ids, reconciled} =
        Enum.reduce(ready, {comment_ids, reconciled}, fn comment, {ids, items} ->
          parent_comment_id = Map.get(ids, comment.parent_comment_node_id)

          item =
            reconcile_comment!(
              operation,
              source,
              pull_request,
              thread_ids,
              snapshot,
              comment,
              parent_comment_id
            )

          {Map.put(ids, comment.node_id, item.record.id), [item | items]}
        end)

      reconcile_comment_batch!(
        blocked,
        operation,
        source,
        pull_request,
        thread_ids,
        snapshot,
        comment_ids,
        reconciled
      )
    end
  end

  defp reconcile_comment!(
         operation,
         source,
         pull_request,
         thread_ids,
         snapshot,
         comment,
         parent_comment_id
       ) do
    existing =
      base_by_extension(
        operation,
        ReviewCommentExtension,
        :review_comment_id,
        ReviewComment,
        comment.node_id
      )

    result =
      SoftwareProving.upsert_provider_resource(operation, source, ReviewComment, existing, %{
        pull_request_id: pull_request.id,
        review_thread_id: Map.get(thread_ids, comment.review_thread_node_id),
        parent_comment_id: parent_comment_id,
        body: comment.body,
        author_label: comment.author_label,
        state: comment.state,
        published_at: comment.published_at,
        provider_version: snapshot.provider_version,
        provider_sequence: snapshot.provider_sequence,
        provider_updated_at: snapshot.provider_updated_at
      })
      |> unwrap!()

    ensure_extension!(
      operation,
      ReviewCommentExtension,
      :review_comment_id,
      result.record.id,
      %{
        node_id: comment.node_id,
        database_id: comment.database_id,
        review_database_id: comment.review_database_id
      }
    )

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
  end

  defp reconcile_checks!(operation, source, repository, pull_request, snapshot) do
    Enum.map(snapshot.check_runs, fn check ->
      existing =
        base_by_extension(
          operation,
          CheckRunExtension,
          :check_run_id,
          CheckRun,
          check.node_id
        )

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

      ensure_extension!(
        operation,
        CheckRunExtension,
        :check_run_id,
        result.record.id,
        %{
          node_id: check.node_id,
          database_id: check.database_id,
          check_suite_database_id: check.check_suite_database_id
        }
      )

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

  defp map_product_work!(operation, comments, checks, review_threads) do
    if is_nil(operation.workspace_id),
      do: [],
      else: map_workspace_product_work!(operation, comments, checks, review_threads)
  end

  defp map_workspace_product_work!(operation, comments, checks, review_threads) do
    thread_states = Map.new(review_threads, &{&1.node_id, &1.state})

    comment_signals =
      Enum.flat_map(comments, fn item ->
        actionable? = review_comment_actionable?(item, thread_states)

        result =
          WorkGraph.sync_integration_signal(
            operation,
            item.reference,
            %{
              title: "Review comment from #{item.record.author_label || "GitHub"}",
              body: item.record.body
            },
            actionable?
          )
          |> unwrap!()

        if actionable?, do: [result.signal.id], else: []
      end)

    check_signals =
      checks
      |> Enum.flat_map(fn item ->
        actionable? = failing_check?(item.record)

        result =
          WorkGraph.sync_integration_signal(
            operation,
            item.reference,
            %{
              title: "Failing check: #{item.record.name}",
              body: "#{item.record.name} concluded with #{item.record.conclusion}."
            },
            actionable?
          )
          |> unwrap!()

        if actionable?, do: [result.signal.id], else: []
      end)

    comment_signals ++ check_signals
  end

  defp review_comment_actionable?(item, thread_states) do
    item.record.state == "published" and
      Map.get(thread_states, item.snapshot.review_thread_node_id, "open") == "open"
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

  defp base_by_extension(operation, extension, base_key, base_resource, node_id) do
    operation
    |> extension_by_node_query(extension, node_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        nil

      {:ok, record} ->
        Ash.get!(base_resource, Map.fetch!(record, base_key),
          action: :read_with_deleted,
          authorize?: false
        )

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp ensure_extension!(operation, extension, base_key, base_id, attrs) do
    operation
    |> extension_by_node_query(extension, attrs.node_id)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        attrs =
          attrs
          |> Map.put(:organization_id, operation.organization_id)
          |> Map.put(:workspace_id, operation.workspace_id)
          |> Map.put(base_key, base_id)

        Repo.ash_create!(extension, attrs)

      {:ok, existing} ->
        if Map.fetch!(existing, base_key) == base_id,
          do: existing,
          else: Repo.rollback(:provider_identity_conflict)

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp extension_by_node_query(operation, extension, node_id) do
    query =
      extension
      |> Ash.Query.filter(organization_id == ^operation.organization_id and node_id == ^node_id)

    if is_nil(operation.workspace_id),
      do: Ash.Query.filter(query, is_nil(workspace_id)),
      else: Ash.Query.filter(query, workspace_id == ^operation.workspace_id)
  end

  defp create_outcome!(operation, request, installation, snapshot, resource, signal_ids, state) do
    attrs = %{
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
      signal_ids: signal_ids,
      failure_class: nil,
      failure_code: nil,
      retry_at: nil
    }

    persist_outcome!(operation.id, attrs)
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
    {failure_class, failure_code, retry_at} = classify_failure(reason)

    case authorized_installation(operation, request) do
      {:ok, installation} ->
        attrs = %{
          id: Ecto.UUID.generate(),
          installation_id: installation.id,
          operation_id: operation.id,
          object_type: request.object_type,
          object_id: request.object_id,
          delivery_id: request.delivery_id,
          state: Atom.to_string(failure_class),
          signal_ids: [],
          failure_class: Atom.to_string(failure_class),
          failure_code: Atom.to_string(failure_code),
          retry_at: retry_at
        }

        case Repo.transaction(fn ->
               lock!("github:sync-outcome:#{operation.id}")
               persist_outcome!(operation.id, attrs)
             end) do
          {:ok, outcome} -> replay_outcome(outcome, request)
          {:error, error} -> {:error, error}
        end

      {:error, _error} ->
        {:error, {failure_class, failure_code}}
    end
  end

  defp classify_failure({:rate_limited, %DateTime{} = reset_at}),
    do: {:retryable, :provider_rate_limited, reset_at}

  defp classify_failure(reason)
       when reason in [:network_error, :provider_unavailable, :unavailable],
       do: {:retryable, :provider_unavailable, nil}

  defp classify_failure(:installation_revoked), do: {:terminal, :installation_revoked, nil}
  defp classify_failure(:invalid_credential), do: {:terminal, :invalid_credential, nil}
  defp classify_failure(:permission_denied), do: {:authorization, :permission_denied, nil}
  defp classify_failure(:adapter_unavailable), do: {:configuration, :adapter_unavailable, nil}
  defp classify_failure(:fixture_not_found), do: {:terminal, :provider_object_not_found, nil}
  defp classify_failure(_reason), do: {:terminal, :invalid_provider_response, nil}

  defp replay_outcome(outcome, request) do
    if outcome.object_type == request.object_type and outcome.object_id == request.object_id and
         outcome.delivery_id == request.delivery_id do
      case outcome.state do
        state when state in ~w(reconciled skipped_stale) -> {:ok, outcome}
        "retryable" -> retryable_outcome(outcome)
        "terminal" -> {:error, {:terminal, known_code(outcome.failure_code)}}
        "authorization" -> {:error, {:authorization, known_code(outcome.failure_code)}}
        "configuration" -> {:error, {:configuration, known_code(outcome.failure_code)}}
      end
    else
      {:error, :forbidden}
    end
  end

  defp retryable_outcome(%SyncOutcome{
         failure_code: "provider_rate_limited",
         retry_at: %DateTime{} = retry_at
       }),
       do: {:error, {:retryable, :provider_rate_limited, retry_at}}

  defp retryable_outcome(outcome),
    do: {:error, {:retryable, known_code(outcome.failure_code)}}

  defp known_code("provider_rate_limited"), do: :provider_rate_limited
  defp known_code("provider_unavailable"), do: :provider_unavailable
  defp known_code("installation_revoked"), do: :installation_revoked
  defp known_code("invalid_credential"), do: :invalid_credential
  defp known_code("permission_denied"), do: :permission_denied
  defp known_code("adapter_unavailable"), do: :adapter_unavailable
  defp known_code("provider_object_not_found"), do: :provider_object_not_found
  defp known_code(_code), do: :invalid_provider_response

  defp outcome_by_operation(operation_id) do
    SyncOutcome
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.read_one(authorize?: false)
  end

  defp persist_outcome!(operation_id, attrs) do
    case outcome_by_operation(operation_id) do
      {:ok, nil} ->
        Repo.ash_create!(SyncOutcome, attrs)

      {:ok, %SyncOutcome{state: "retryable"} = outcome} ->
        result_attrs =
          Map.drop(attrs, [
            :id,
            :installation_id,
            :operation_id,
            :object_type,
            :object_id,
            :delivery_id
          ])

        outcome
        |> Ash.Changeset.for_update(:record_result, result_attrs)
        |> Repo.ash_update!()

      {:ok, outcome} ->
        outcome

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp terminalize_retry!(operation_id, request, failure_code) do
    case outcome_by_operation(operation_id) do
      {:ok, %SyncOutcome{} = outcome} ->
        if outcome_matches_request?(outcome, request) and
             known_code(outcome.failure_code) == failure_code do
          terminalize_retry_outcome!(outcome, failure_code)
        else
          Repo.rollback(:forbidden)
        end

      {:ok, nil} ->
        Repo.rollback(:sync_outcome_not_found)

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp terminalize_retry_outcome!(%SyncOutcome{state: "retryable"} = outcome, failure_code) do
    outcome
    |> Ash.Changeset.for_update(:record_result, %{
      state: "terminal",
      failure_class: "terminal",
      failure_code: Atom.to_string(failure_code),
      retry_at: nil
    })
    |> Repo.ash_update!()
  end

  defp terminalize_retry_outcome!(%SyncOutcome{state: "terminal"} = outcome, _failure_code),
    do: outcome

  defp terminalize_retry_outcome!(_outcome, _failure_code),
    do: Repo.rollback(:invalid_sync_outcome_state)

  defp outcome_matches_request?(outcome, request) do
    outcome.object_type == request.object_type and outcome.object_id == request.object_id and
      outcome.delivery_id == request.delivery_id
  end

  defp lock!(key), do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

  defp resource_type(record),
    do: record.__struct__ |> Module.split() |> List.last() |> Macro.underscore()

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: Repo.rollback(error)
end
