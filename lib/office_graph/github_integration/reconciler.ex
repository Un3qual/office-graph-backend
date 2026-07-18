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
    OutboundAction,
    RecordLoader,
    ReconciliationRequest,
    ReviewReplyMarker,
    SecretStore,
    StorageResult,
    SyncOutcome
  }

  alias OfficeGraph.ExternalRefs.ExternalReference

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
  @retryable_failure_codes [
    :provider_rate_limited,
    :provider_unavailable,
    :integration_storage_unavailable
  ]
  @pre_operation_failure_codes @retryable_failure_codes ++
                                 [
                                   :installation_revoked,
                                   :invalid_credential,
                                   :invalid_delivery_archive,
                                   :invalid_delivery_payload,
                                   :invalid_worker_result
                                 ]
  @finished_failure_states ~w(terminal authorization configuration)

  require Ash.Query

  def reconcile(operation, %ReconciliationRequest{} = request) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile) do
      case outcome_by_operation(operation.id) do
        {:ok, outcome} -> continue_or_replay(operation, request, outcome)
        {:error, :integration_storage_unavailable} -> retryable_storage_error()
      end
    end
  end

  def reconcile(_operation, _request), do: {:error, :forbidden}

  def exhaust_retry(operation, %ReconciliationRequest{} = request, failure_code) do
    if failure_code in @retryable_failure_codes do
      finalize_failure(operation, request, Atom.to_string(failure_code))
    else
      {:error, :forbidden}
    end
  end

  def exhaust_retry(_operation, _request, _failure_code), do: {:error, :forbidden}

  def finalize_failure(operation, %ReconciliationRequest{} = request, failure_code) do
    with :ok <- Operations.validate_system_operation(operation, :integration_reconcile),
         :ok <- validate_retry_request_authority(operation, request),
         {:ok, failure_code_atom} <- persisted_failure_code(failure_code) do
      StorageResult.run(fn ->
        Repo.transaction(fn ->
          lock!("github:sync-outcome:#{operation.id}")

          finalize_failure!(
            operation,
            request,
            failure_code_atom,
            failure_code
          )
        end)
      end)
    end
  end

  def finalize_failure(_operation, _request, _failure_code), do: {:error, :forbidden}

  defp validate_retry_request_authority(operation, request) do
    if operation.authority_basis == "github_installation:#{request.installation_id}",
      do: :ok,
      else: {:error, :forbidden}
  end

  def exhaust_pre_operation(operation, installation_id, delivery_id, failure_code)
      when is_binary(installation_id) and is_binary(delivery_id) and
             failure_code in @pre_operation_failure_codes do
    with :ok <- Operations.validate_system_operation(operation, :provider_webhook_receive) do
      attrs =
        terminal_outcome_attrs(
          operation,
          installation_id,
          "provider_delivery",
          delivery_id,
          delivery_id,
          failure_code
        )

      persist_pre_operation(operation, attrs)
    end
  end

  def exhaust_pre_operation(_operation, _installation_id, _delivery_id, _failure_code),
    do: {:error, :forbidden}

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
    case authorized_installation(operation, request) do
      {:ok, installation} ->
        reconcile_provider(operation, request, installation)

      {:error, {:installation_revoked, installation}} ->
        record_failure(operation, request, installation, :installation_revoked)

      {:error, :integration_storage_unavailable} ->
        record_storage_failure(operation, request)

      error ->
        error
    end
  end

  defp reconcile_provider(operation, request, installation) do
    with {:ok, credential} <- resolve_credential(operation, installation),
         {:ok, source} <- Integrations.ensure_provider_source("github", "GitHub"),
         {:ok, snapshot} <- fetch_snapshot(request, installation, credential) do
      reconcile_snapshot(operation, request, installation, source, snapshot)
    else
      {:error, {:provider, reason}} -> record_failure(operation, request, installation, reason)
      {:error, :integration_storage_unavailable} -> record_storage_failure(operation, request)
      {:error, _error} = error -> error
    end
  end

  defp authorized_installation(operation, request) do
    case RecordLoader.get(Installation, request.installation_id,
           authorize?: false,
           not_found_error?: false
         ) do
      {:ok,
       %Installation{
         organization_id: organization_id,
         workspace_id: workspace_id,
         service_principal_id: principal_id
       } = installation}
      when organization_id == operation.organization_id and
             workspace_id == operation.workspace_id and
             principal_id == operation.principal_id ->
        cond do
          operation.authority_basis != "github_installation:#{installation.id}" ->
            {:error, :forbidden}

          installation.lifecycle_state == "active" ->
            {:ok, installation}

          true ->
            {:error, {:installation_revoked, installation}}
        end

      {:ok, _missing_or_cross_scope} ->
        {:error, :forbidden}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp resolve_credential(operation, installation) do
    query =
      Ash.Query.filter(
        InstallationCredential,
        installation_id == ^installation.id and purpose == "app_private_key" and
          credential_id == ^operation.credential_id
      )

    case RecordLoader.read_one(InstallationCredential, query, authorize?: false) do
      {:ok, %InstallationCredential{credential_id: credential_id}} ->
        credential_id
        |> SecretStore.resolve(%{
          organization_id: installation.organization_id,
          workspace_id: installation.workspace_id
        })
        |> classify_credential_resolution()

      {:ok, _missing_or_invalid} ->
        {:error, :forbidden}

      {:error, _storage_error} ->
        {:error, :integration_storage_unavailable}
    end
  end

  defp classify_credential_resolution({:ok, credential}), do: {:ok, credential}

  defp classify_credential_resolution({:error, :integration_storage_unavailable}),
    do: {:error, :integration_storage_unavailable}

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
        matching_pull_request_scope?(snapshot, request) and
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

  defp matching_pull_request_scope?(snapshot, %{
         object_type: "check_run",
         pull_request_id: pull_request_id
       })
       when is_binary(pull_request_id),
       do: provider_object_matches?(snapshot.pull_request, pull_request_id)

  defp matching_pull_request_scope?(_snapshot, _request), do: true

  defp provider_object_matches?(object, object_id) do
    object.node_id == object_id or
      (is_integer(object.database_id) and Integer.to_string(object.database_id) == object_id)
  end

  defp valid_repository?(%Adapter.RepositorySnapshot{} = repository) do
    nonblank_string?(repository.node_id) and optional_positive_integer?(repository.database_id) and
      valid_optional_provider_metadata?(repository) and
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
      valid_optional_provider_metadata?(comment) and optional_datetime?(comment.published_at) and
      optional_string?(comment.url)
  end

  defp valid_review_comment?(_comment), do: false

  defp valid_review_comment_body?(%{state: "published", body: body}),
    do: nonblank_string?(body)

  defp valid_review_comment_body?(%{body: body}), do: is_binary(body)

  defp valid_check_run?(%Adapter.CheckRunSnapshot{} = check) do
    nonblank_string?(check.node_id) and optional_positive_integer?(check.database_id) and
      optional_positive_integer?(check.check_suite_database_id) and nonblank_string?(check.name) and
      check.status in @check_statuses and valid_check_state?(check) and
      valid_optional_provider_metadata?(check) and
      is_boolean(check.current?) and
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

  defp valid_optional_provider_metadata?(item),
    do: provider_metadata(item) != :invalid

  defp provider_metadata(item) do
    case {
      Map.get(item, :provider_version),
      Map.get(item, :provider_sequence),
      Map.get(item, :provider_updated_at)
    } do
      {nil, nil, nil} ->
        :missing

      {version, sequence, updated_at} ->
        if nonblank_string?(version) and is_integer(sequence) and sequence >= 0 and
             optional_datetime?(updated_at) do
          {:ok,
           %Adapter.ProviderMetadata{
             version: version,
             sequence: sequence,
             updated_at: updated_at
           }}
        else
          :invalid
        end
    end
  end

  defp valid_collection?(items, validator) when is_list(items), do: Enum.all?(items, validator)
  defp valid_collection?(_items, _validator), do: false

  defp unique_node_ids?(items) when is_list(items) do
    ids = Enum.map(items, & &1.node_id)
    Enum.uniq(ids) == ids
  end

  defp valid_comment_parents?(comments) when is_list(comments) do
    parent_by_node = Map.new(comments, &{&1.node_id, &1.parent_comment_node_id})

    Enum.all?(comments, fn comment ->
      is_nil(comment.parent_comment_node_id) or
        (comment.parent_comment_node_id != comment.node_id and
           Map.has_key?(parent_by_node, comment.parent_comment_node_id))
    end) and acyclic_comment_parents?(parent_by_node)
  end

  defp acyclic_comment_parents?(parent_by_node) do
    not match?(
      :cycle,
      Enum.reduce_while(Map.keys(parent_by_node), %{}, fn node_id, states ->
        case visit_comment_parent(node_id, parent_by_node, states) do
          {:ok, states} -> {:cont, states}
          :cycle -> {:halt, :cycle}
        end
      end)
    )
  end

  defp visit_comment_parent(node_id, parent_by_node, states) do
    case Map.get(states, node_id) do
      :visited ->
        {:ok, states}

      :visiting ->
        :cycle

      nil ->
        states = Map.put(states, node_id, :visiting)

        case Map.fetch!(parent_by_node, node_id) do
          nil ->
            {:ok, Map.put(states, node_id, :visited)}

          parent_node_id ->
            case visit_comment_parent(parent_node_id, parent_by_node, states) do
              {:ok, states} -> {:ok, Map.put(states, node_id, :visited)}
              :cycle -> :cycle
            end
        end
    end
  end

  defp valid_comment_threads?(comments, threads) when is_list(comments) and is_list(threads) do
    thread_node_ids = MapSet.new(threads, & &1.node_id)
    comments_by_node = Map.new(comments, &{&1.node_id, &1})

    Enum.all?(comments, &valid_comment_thread?(&1, thread_node_ids, comments_by_node))
  end

  defp valid_comment_thread?(comment, thread_node_ids, comments_by_node) do
    valid_declared_thread? =
      is_nil(comment.review_thread_node_id) or
        MapSet.member?(thread_node_ids, comment.review_thread_node_id)

    valid_parent_thread? =
      case comment.parent_comment_node_id do
        nil ->
          true

        parent_node_id ->
          parent_thread =
            effective_comment_thread(
              Map.fetch!(comments_by_node, parent_node_id),
              comments_by_node
            )

          is_nil(comment.review_thread_node_id) or
            comment.review_thread_node_id == parent_thread
      end

    valid_declared_thread? and valid_parent_thread?
  end

  defp effective_comment_thread(%{review_thread_node_id: thread_node_id}, _comments_by_node)
       when not is_nil(thread_node_id),
       do: thread_node_id

  defp effective_comment_thread(%{parent_comment_node_id: nil}, _comments_by_node), do: nil

  defp effective_comment_thread(comment, comments_by_node) do
    comment.parent_comment_node_id
    |> then(&Map.fetch!(comments_by_node, &1))
    |> effective_comment_thread(comments_by_node)
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
      {:error, :integration_storage_unavailable} -> retryable_storage_error()
      {:error, error} when is_struct(error) -> retryable_storage_error()
      {:error, error} -> {:error, error}
    end
  end

  defp persist_snapshot!(operation, request, installation, source, snapshot) do
    repository = reconcile_repository!(operation, source, snapshot)
    pull_request = reconcile_pull_request!(operation, source, repository, snapshot)

    if older_pull_request_snapshot?(request, pull_request.record, snapshot) do
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
      thread_records = reconcile_threads!(operation, source, pull_request.record, snapshot)
      thread_ids = Map.new(thread_records, fn {node_id, record} -> {node_id, record.id} end)
      comments = reconcile_comments!(operation, source, pull_request.record, thread_ids, snapshot)

      checks =
        reconcile_checks!(operation, source, repository.record, pull_request.record, snapshot)

      missing_references =
        if pull_request_snapshot_older?(pull_request.record, snapshot) do
          []
        else
          missing_product_references!(
            operation,
            source,
            pull_request.record,
            comments,
            checks,
            snapshot
          )
        end

      signal_ids =
        map_product_work!(operation, comments, checks, thread_records, missing_references)

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

  defp older_pull_request_snapshot?(%{object_type: "pull_request"}, pull_request, snapshot),
    do: pull_request_snapshot_older?(pull_request, snapshot)

  defp older_pull_request_snapshot?(_request, _pull_request, _snapshot), do: false

  defp pull_request_snapshot_older?(pull_request, snapshot),
    do: snapshot.provider_sequence < pull_request.provider_sequence

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

    provider = repository_provider_metadata(snapshot.repository, snapshot)

    result =
      SoftwareProving.upsert_provider_resource(operation, source, Repository, existing, %{
        name: snapshot.repository.name,
        full_name: snapshot.repository.full_name,
        default_ref_name: snapshot.repository.default_ref_name,
        visibility: snapshot.repository.visibility,
        provider_version: provider.version,
        provider_sequence: provider.sequence,
        provider_updated_at: provider.updated_at
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
      snapshot.repository.url,
      result.status
    )

    result
  end

  defp repository_provider_metadata(repository, snapshot) do
    case provider_metadata(repository) do
      {:ok, provider} ->
        provider

      :missing ->
        %Adapter.ProviderMetadata{
          version: Adapter.ProviderDigest.repository(repository),
          sequence: snapshot.provider_sequence,
          updated_at: snapshot.provider_updated_at
        }
    end
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
      snapshot.pull_request.url,
      result.status
    )

    result
  end

  defp reconcile_threads!(operation, source, pull_request, snapshot) do
    Map.new(snapshot.review_threads, fn thread ->
      provider = thread_provider_metadata(thread, snapshot)

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
          provider_version: provider.version,
          provider_sequence: provider.sequence,
          provider_updated_at: provider.updated_at
        })
        |> unwrap!()

      ensure_extension!(
        operation,
        ReviewThreadExtension,
        :review_thread_id,
        result.record.id,
        %{node_id: thread.node_id}
      )

      {thread.node_id, result.record}
    end)
  end

  defp thread_provider_metadata(thread, snapshot) do
    digest =
      [
        thread.node_id,
        thread.state,
        thread.path,
        thread.line,
        thread.side,
        thread.resolved_at
      ]
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %Adapter.ProviderMetadata{
      version: "github-review-thread:v1:#{digest}",
      sequence: snapshot.provider_sequence,
      updated_at: snapshot.provider_updated_at
    }
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
         _comment_records,
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
         comment_records,
         reconciled
       ) do
    {ready, blocked} =
      Enum.split_with(pending, fn comment ->
        is_nil(comment.parent_comment_node_id) or
          Map.has_key?(comment_records, comment.parent_comment_node_id)
      end)

    if ready == [] do
      Repo.rollback(:invalid_provider_response)
    else
      {comment_records, reconciled} =
        Enum.reduce(ready, {comment_records, reconciled}, fn comment, {records, items} ->
          parent_comment = Map.get(records, comment.parent_comment_node_id)
          parent_comment_id = parent_comment && parent_comment.id

          review_thread_id =
            Map.get(thread_ids, comment.review_thread_node_id) ||
              (parent_comment && parent_comment.review_thread_id)

          item =
            reconcile_comment!(
              operation,
              source,
              pull_request,
              snapshot,
              comment,
              parent_comment_id,
              review_thread_id
            )

          {Map.put(records, comment.node_id, item.record), [item | items]}
        end)

      reconcile_comment_batch!(
        blocked,
        operation,
        source,
        pull_request,
        thread_ids,
        snapshot,
        comment_records,
        reconciled
      )
    end
  end

  defp reconcile_comment!(
         operation,
         source,
         pull_request,
         snapshot,
         comment,
         parent_comment_id,
         review_thread_id
       ) do
    provider = comment_provider_metadata(comment, snapshot)

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
        review_thread_id: review_thread_id,
        parent_comment_id: parent_comment_id,
        body: comment.body,
        author_label: comment.author_label,
        state: comment.state,
        published_at: comment.published_at,
        provider_version: provider.version,
        provider_sequence: provider.sequence,
        provider_updated_at: provider.updated_at
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
        comment.url,
        result.status
      )

    %{record: result.record, snapshot: comment, reference: reference, status: result.status}
  end

  defp comment_provider_metadata(comment, snapshot) do
    case provider_metadata(comment) do
      {:ok, provider} -> provider
      :missing -> derived_comment_provider_metadata(comment, snapshot)
    end
  end

  defp derived_comment_provider_metadata(comment, snapshot) do
    digest =
      [
        comment.node_id,
        comment.database_id,
        comment.review_database_id,
        comment.review_thread_node_id,
        comment.parent_comment_node_id,
        comment.body,
        comment.author_label,
        comment.state,
        comment.published_at,
        comment.url
      ]
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    %Adapter.ProviderMetadata{
      version: "github-review-comment:v1:#{digest}",
      sequence: snapshot.provider_sequence,
      updated_at: snapshot.provider_updated_at
    }
  end

  defp reconcile_checks!(operation, source, repository, pull_request, snapshot) do
    Enum.map(snapshot.check_runs, fn check ->
      existing =
        check_run_by_extension(operation, check.node_id, pull_request.id)

      provider = check_provider_metadata(check, snapshot, existing)

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
          provider_version: provider.version,
          provider_sequence: provider.sequence,
          provider_updated_at: provider.updated_at
        })
        |> unwrap!()

      ensure_check_run_extension!(
        operation,
        result.record.id,
        %{
          pull_request_id: pull_request.id,
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
          "#{check.node_id}:pull_request:#{snapshot.pull_request.node_id}",
          check.details_url,
          result.status
        )

      %{record: result.record, snapshot: check, reference: reference, status: result.status}
    end)
  end

  defp check_provider_metadata(check, snapshot, existing) do
    case provider_metadata(check) do
      {:ok, provider} ->
        provider

      :missing ->
        derived_check_provider_metadata(check, snapshot, existing)
    end
  end

  defp derived_check_provider_metadata(check, snapshot, existing) do
    version = Adapter.ProviderDigest.check_run(check)

    sequence =
      case existing do
        nil ->
          snapshot.provider_sequence

        %{provider_version: ^version, provider_sequence: sequence} ->
          sequence

        %{provider_sequence: sequence} when check.status in ~w(queued in_progress) ->
          max(snapshot.provider_sequence, (sequence || -1) + 1)

        _existing ->
          snapshot.provider_sequence
      end

    %Adapter.ProviderMetadata{
      version: version,
      sequence: sequence,
      updated_at: snapshot.provider_updated_at
    }
  end

  defp missing_product_references!(
         operation,
         source,
         pull_request,
         comments,
         checks,
         snapshot
       ) do
    missing_comments =
      missing_provider_resources!(
        operation,
        source,
        ReviewComment,
        pull_request.id,
        Enum.map(comments, & &1.record.id)
      )

    missing_checks =
      missing_provider_resources!(
        operation,
        source,
        CheckRun,
        pull_request.id,
        checks
        |> Enum.filter(& &1.snapshot.current?)
        |> Enum.map(& &1.record.id)
      )

    tombstoned_comments =
      Enum.map(missing_comments, fn comment ->
        SoftwareProving.upsert_provider_resource(
          operation,
          source,
          ReviewComment,
          comment,
          %{
            state: "deleted",
            provider_version:
              "office-graph:github:review-comment-absent:#{snapshot.provider_version}",
            provider_sequence: max(snapshot.provider_sequence, comment.provider_sequence || -1),
            provider_updated_at: snapshot.provider_updated_at || comment.provider_updated_at
          }
        )
        |> unwrap!()
        |> Map.fetch!(:record)
      end)

    tombstoned_checks =
      Enum.map(missing_checks, fn check ->
        SoftwareProving.upsert_provider_resource(
          operation,
          source,
          CheckRun,
          check,
          %{
            provider_version: "office-graph:github:check-run-absent:#{snapshot.provider_version}",
            provider_sequence: max(snapshot.provider_sequence, check.provider_sequence || -1),
            provider_updated_at: snapshot.provider_updated_at || check.provider_updated_at
          }
        )
        |> unwrap!()
        |> Map.fetch!(:record)
      end)

    missing_provider_references!(
      operation,
      source,
      "review_comment",
      Enum.map(tombstoned_comments, & &1.id)
    ) ++
      missing_provider_references!(
        operation,
        source,
        "check_run",
        Enum.map(tombstoned_checks, & &1.id)
      )
  end

  defp missing_provider_resources!(operation, source, resource, pull_request_id, current_ids) do
    current_ids = MapSet.new(current_ids)

    query =
      resource
      |> Ash.Query.filter(
        organization_id == ^operation.organization_id and source_id == ^source.id and
          pull_request_id == ^pull_request_id and lifecycle_state == "active"
      )
      |> scope_query(operation.workspace_id)

    case RecordLoader.read(resource, query, authorize?: false) do
      {:ok, records} -> Enum.reject(records, &MapSet.member?(current_ids, &1.id))
      {:error, _storage_error} -> Repo.rollback(:integration_storage_unavailable)
    end
  end

  defp missing_provider_references!(operation, source, object_type, missing_ids) do
    case missing_ids do
      [] ->
        []

      missing_ids ->
        query =
          ExternalReference
          |> Ash.Query.filter(
            organization_id == ^operation.organization_id and source_id == ^source.id and
              provider == "github" and object_type == ^object_type and
              resource_type == ^object_type and resource_id in ^missing_ids
          )
          |> scope_query(operation.workspace_id)

        case RecordLoader.read(ExternalReference, query, authorize?: false) do
          {:ok, references} -> references
          {:error, _storage_error} -> Repo.rollback(:integration_storage_unavailable)
        end
    end
  end

  defp scope_query(query, nil), do: Ash.Query.filter(query, is_nil(workspace_id))

  defp scope_query(query, workspace_id),
    do: Ash.Query.filter(query, workspace_id == ^workspace_id)

  defp map_product_work!(operation, comments, checks, thread_records, missing_references) do
    if is_nil(operation.workspace_id),
      do: [],
      else:
        map_workspace_product_work!(
          operation,
          comments,
          checks,
          thread_records,
          missing_references
        )
  end

  defp map_workspace_product_work!(
         operation,
         comments,
         checks,
         thread_records,
         missing_references
       ) do
    thread_states =
      Map.new(thread_records, fn {_node_id, record} -> {record.id, record.state} end)

    comment_signals =
      Enum.flat_map(comments, fn item ->
        if item.status == :stale do
          []
        else
          actionable? = review_comment_actionable?(operation, item, thread_states)

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
        end
      end)

    check_signals =
      checks
      |> Enum.flat_map(fn item ->
        if not item.snapshot.current? or item.status == :stale do
          []
        else
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
        end
      end)

    Enum.each(missing_references, fn reference ->
      operation
      |> WorkGraph.sync_integration_signal(reference, %{}, false)
      |> unwrap!()
    end)

    comment_signals ++ check_signals
  end

  defp review_comment_actionable?(operation, item, thread_states) do
    item.record.state == "published" and not authenticated_own_reply?(operation, item) and
      case item.record.review_thread_id do
        nil -> true
        thread_id -> Map.get(thread_states, thread_id) == "open"
      end
  end

  defp authenticated_own_reply?(operation, item) do
    case ReviewReplyMarker.action_id(item.record.body) do
      nil ->
        false

      action_id ->
        case RecordLoader.get(OutboundAction, action_id,
               authorize?: false,
               not_found_error?: false
             ) do
          {:ok, %OutboundAction{} = action} ->
            authenticated_reply_action?(operation, item, action)

          {:ok, nil} ->
            false

          {:error, _storage_error} ->
            Repo.rollback(:integration_storage_unavailable)
        end
    end
  end

  defp authenticated_reply_action?(operation, item, action) do
    action.state == "succeeded" and action.action_kind == "review_reply" and
      action.target_type == "review_comment" and
      action.organization_id == operation.organization_id and
      action.workspace_id == operation.workspace_id and
      operation.authority_basis == "github_installation:#{action.installation_id}" and
      action.provider_response_id in provider_comment_identities(item.snapshot)
  end

  defp provider_comment_identities(snapshot) do
    [snapshot.node_id, optional_database_identity(snapshot.database_id)]
    |> Enum.reject(&is_nil/1)
  end

  defp optional_database_identity(database_id) when is_integer(database_id),
    do: Integer.to_string(database_id)

  defp optional_database_identity(_database_id), do: nil

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

  defp maybe_reference!(_operation, _source, _record, _object_type, _node_id, _url, :stale),
    do: nil

  defp maybe_reference!(operation, source, record, object_type, node_id, url, _status),
    do: maybe_reference!(operation, source, record, object_type, node_id, url)

  defp base_by_extension(operation, extension, base_key, base_resource, node_id) do
    case extension_by_node!(operation, extension, node_id) do
      nil ->
        nil

      record ->
        case RecordLoader.get(base_resource, Map.fetch!(record, base_key),
               action: :read_with_deleted,
               authorize?: false,
               not_found_error?: false
             ) do
          {:ok, base_record} -> base_record
          {:error, _storage_error} -> Repo.rollback(:integration_storage_unavailable)
        end
    end
  end

  defp check_run_by_extension(operation, node_id, pull_request_id) do
    case check_run_extension!(operation, node_id, pull_request_id) do
      nil ->
        nil

      extension ->
        case RecordLoader.get(CheckRun, extension.check_run_id,
               action: :read_with_deleted,
               authorize?: false,
               not_found_error?: false
             ) do
          {:ok, check_run} -> check_run
          {:error, _storage_error} -> Repo.rollback(:integration_storage_unavailable)
        end
    end
  end

  defp ensure_check_run_extension!(operation, check_run_id, attrs) do
    case check_run_extension!(operation, attrs.node_id, attrs.pull_request_id) do
      nil ->
        attrs
        |> Map.put(:organization_id, operation.organization_id)
        |> Map.put(:workspace_id, operation.workspace_id)
        |> Map.put(:check_run_id, check_run_id)
        |> then(&Repo.ash_create!(CheckRunExtension, &1))

      existing ->
        if existing.check_run_id == check_run_id,
          do: existing,
          else: Repo.rollback(:provider_identity_conflict)
    end
  end

  defp check_run_extension!(operation, node_id, pull_request_id) do
    operation
    |> extension_by_node_query(CheckRunExtension, node_id)
    |> Ash.Query.filter(pull_request_id == ^pull_request_id)
    |> then(&RecordLoader.read_one(CheckRunExtension, &1, authorize?: false))
    |> case do
      {:ok, extension} -> extension
      {:error, _storage_error} -> Repo.rollback(:integration_storage_unavailable)
    end
  end

  defp ensure_extension!(operation, extension, base_key, base_id, attrs) do
    case extension_by_node!(operation, extension, attrs.node_id) do
      nil ->
        attrs =
          attrs
          |> Map.put(:organization_id, operation.organization_id)
          |> Map.put(:workspace_id, operation.workspace_id)
          |> Map.put(base_key, base_id)

        Repo.ash_create!(extension, attrs)

      existing ->
        if Map.fetch!(existing, base_key) == base_id,
          do: existing,
          else: Repo.rollback(:provider_identity_conflict)
    end
  end

  defp extension_by_node!(operation, extension, node_id) do
    operation
    |> extension_by_node_query(extension, node_id)
    |> then(&RecordLoader.read_one(extension, &1, authorize?: false))
    |> case do
      {:ok, record} -> record
      {:error, _storage_error} -> Repo.rollback(:integration_storage_unavailable)
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

  defp record_failure(operation, request, installation, reason) do
    {failure_class, failure_code, retry_at} = classify_failure(reason)
    failure_class_name = Atom.to_string(failure_class)

    attrs = %{
      id: Ecto.UUID.generate(),
      installation_id: installation.id,
      operation_id: operation.id,
      object_type: request.object_type,
      object_id: request.object_id,
      delivery_id: request.delivery_id,
      state: failure_class_name,
      signal_ids: [],
      failure_class: failure_class_name,
      failure_code: Atom.to_string(failure_code),
      retry_at: retry_at
    }

    case StorageResult.run(fn ->
           Repo.transaction(fn ->
             lock!("github:sync-outcome:#{operation.id}")

             outcome = persist_outcome!(operation.id, attrs)
             persist_installation_failure!(installation, failure_code, outcome)
             outcome
           end)
         end) do
      {:ok, outcome} -> replay_outcome(outcome, request)
      {:error, :integration_storage_unavailable} -> retryable_storage_error()
    end
  end

  defp record_storage_failure(operation, request) do
    attrs = %{
      id: Ecto.UUID.generate(),
      installation_id: request.installation_id,
      operation_id: operation.id,
      object_type: request.object_type,
      object_id: request.object_id,
      delivery_id: request.delivery_id,
      state: "retryable",
      signal_ids: [],
      failure_class: "retryable",
      failure_code: "integration_storage_unavailable",
      retry_at: nil
    }

    case StorageResult.run(fn ->
           Repo.transaction(fn ->
             lock!("github:sync-outcome:#{operation.id}")
             persist_outcome!(operation.id, attrs)
           end)
         end) do
      {:ok, outcome} -> replay_outcome(outcome, request)
      {:error, :integration_storage_unavailable} -> retryable_storage_error()
    end
  end

  defp persist_installation_failure!(
         installation,
         :installation_revoked,
         %SyncOutcome{state: "terminal", failure_code: "installation_revoked"}
       ) do
    installation
    |> Ash.Changeset.for_update(:set_lifecycle, %{lifecycle_state: "revoked"})
    |> Repo.ash_update!()
  end

  defp persist_installation_failure!(_installation, _failure_code, _outcome), do: :ok

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
  defp known_code("integration_storage_unavailable"), do: :integration_storage_unavailable
  defp known_code("installation_revoked"), do: :installation_revoked
  defp known_code("invalid_credential"), do: :invalid_credential
  defp known_code("permission_denied"), do: :permission_denied
  defp known_code("adapter_unavailable"), do: :adapter_unavailable
  defp known_code("provider_object_not_found"), do: :provider_object_not_found
  defp known_code(_code), do: :invalid_provider_response

  defp persisted_failure_code("provider_rate_limited"), do: {:ok, :provider_rate_limited}
  defp persisted_failure_code("provider_unavailable"), do: {:ok, :provider_unavailable}

  defp persisted_failure_code("integration_storage_unavailable"),
    do: {:ok, :integration_storage_unavailable}

  defp persisted_failure_code("installation_revoked"), do: {:ok, :installation_revoked}
  defp persisted_failure_code("invalid_credential"), do: {:ok, :invalid_credential}
  defp persisted_failure_code("permission_denied"), do: {:ok, :permission_denied}
  defp persisted_failure_code("adapter_unavailable"), do: {:ok, :adapter_unavailable}

  defp persisted_failure_code("provider_object_not_found"),
    do: {:ok, :provider_object_not_found}

  defp persisted_failure_code("invalid_provider_response"),
    do: {:ok, :invalid_provider_response}

  defp persisted_failure_code(_failure_code), do: {:error, :forbidden}

  defp outcome_by_operation(operation_id) do
    SyncOutcome
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> then(&RecordLoader.read_one(SyncOutcome, &1, authorize?: false))
    |> case do
      {:ok, outcome} -> {:ok, outcome}
      {:error, _storage_error} -> {:error, :integration_storage_unavailable}
    end
  end

  defp retryable_storage_error,
    do: {:error, {:retryable, :integration_storage_unavailable}}

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

  defp finalize_failure!(operation, request, failure_code_atom, failure_code) do
    case outcome_by_operation(operation.id) do
      {:ok, %SyncOutcome{} = outcome} ->
        if outcome_matches_request?(outcome, request) do
          cond do
            outcome.state == "retryable" and failure_code_atom in @retryable_failure_codes ->
              terminalize_retry_outcome!(outcome, failure_code_atom)

            outcome.state in @finished_failure_states and outcome.failure_code == failure_code ->
              outcome

            true ->
              Repo.rollback(:forbidden)
          end
        else
          Repo.rollback(:forbidden)
        end

      {:ok, nil} when failure_code_atom in @retryable_failure_codes ->
        attrs =
          terminal_outcome_attrs(
            operation,
            request.installation_id,
            request.object_type,
            request.object_id,
            request.delivery_id,
            failure_code_atom
          )

        persist_outcome!(operation.id, attrs)

      {:ok, nil} ->
        Repo.rollback(:forbidden)

      {:error, error} ->
        Repo.rollback(error)
    end
  end

  defp terminal_outcome_attrs(
         operation,
         installation_id,
         object_type,
         object_id,
         delivery_id,
         failure_code
       ) do
    %{
      id: Ecto.UUID.generate(),
      installation_id: installation_id,
      operation_id: operation.id,
      object_type: object_type,
      object_id: object_id,
      delivery_id: delivery_id,
      state: "terminal",
      signal_ids: [],
      failure_class: "terminal",
      failure_code: Atom.to_string(failure_code),
      retry_at: nil
    }
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

  defp persist_pre_operation(operation, attrs) do
    StorageResult.run(fn ->
      Repo.transaction(fn ->
        lock!("github:sync-outcome:#{operation.id}")
        outcome = persist_outcome!(operation.id, attrs)

        if pre_operation_outcome?(outcome, attrs),
          do: outcome,
          else: Repo.rollback(:forbidden)
      end)
    end)
  end

  defp pre_operation_outcome?(outcome, attrs) do
    outcome.installation_id == attrs.installation_id and
      outcome.object_type == attrs.object_type and outcome.object_id == attrs.object_id and
      outcome.delivery_id == attrs.delivery_id and outcome.state == attrs.state and
      outcome.failure_class == attrs.failure_class and outcome.failure_code == attrs.failure_code
  end

  defp lock!(key), do: Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])

  defp resource_type(record),
    do: record.__struct__ |> Module.split() |> List.last() |> Macro.underscore()

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: Repo.rollback(error)
end
