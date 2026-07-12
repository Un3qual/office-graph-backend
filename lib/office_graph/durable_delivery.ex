defmodule OfficeGraph.DurableDelivery do
  @moduledoc """
  Public boundary for durable domain events, jobs, and projection invalidation.
  """

  use Boundary,
    deps: [
      OfficeGraph.Authorization,
      OfficeGraph.Identity,
      OfficeGraph.Operations,
      OfficeGraph.Repo
    ],
    exports: [DomainEvent, ProjectionInvalidation, TerminalJob]

  alias OfficeGraph.DurableDelivery.{
    DispatchEventWorker,
    DomainEvent,
    EventRequest,
    ProjectionInvalidation,
    Subscriptions,
    TerminalJob
  }

  alias OfficeGraph.Repo

  import Ecto.Query

  require Ash.Query

  def record_and_enqueue(session_context, operation, attrs) do
    with {:ok, request} <- EventRequest.new(session_context, operation, attrs) do
      transaction(fn -> record_and_enqueue_request(request) end)
    end
  end

  def subscribe(session_context, organization_id, workspace_id) do
    Subscriptions.subscribe(session_context, organization_id, workspace_id)
  end

  @doc false
  def subscription_children do
    [
      {Registry, keys: :unique, name: OfficeGraph.DurableDelivery.SubscriptionRegistry},
      {DynamicSupervisor,
       strategy: :one_for_one, name: OfficeGraph.DurableDelivery.SubscriptionSupervisor}
    ]
  end

  def list_terminal_jobs(session_context, opts \\ []) do
    with :ok <- authorize_terminal_read(session_context) do
      limit = opts |> Keyword.get(:limit, 50) |> normalize_limit()

      jobs =
        Oban.Job
        |> where(
          [job],
          job.state in ["cancelled", "discarded"] and
            fragment("?->>'organization_id'", job.args) == ^session_context.organization_id and
            fragment("?->>'workspace_id'", job.args) == ^session_context.workspace_id
        )
        |> order_by([job],
          desc:
            fragment(
              "COALESCE(?, ?, ?, ?)",
              job.cancelled_at,
              job.discarded_at,
              job.attempted_at,
              job.inserted_at
            ),
          desc: job.id
        )
        |> limit(^limit)
        |> Repo.all()

      failure_codes = failure_codes_by_event(jobs)

      {:ok,
       Enum.map(jobs, fn job ->
         failure_code =
           Map.get(failure_codes, job.args["event_id"]) || terminal_failure_code(job)

         %TerminalJob{
           id: job.id,
           worker: job.worker,
           queue: job.queue,
           state: job.state,
           attempt: job.attempt,
           max_attempts: job.max_attempts,
           failure_code: failure_code,
           attempted_at: job.attempted_at,
           cancelled_at: job.cancelled_at,
           discarded_at: job.discarded_at
         }
       end)}
    end
  end

  def dispatch(event_id) when is_binary(event_id),
    do: dispatch_safely(event_id, nil, Subscriptions)

  def dispatch(_event_id), do: {:error, {:terminal, :invalid_event_id}}

  @doc false
  def dispatch(event_id, broadcaster) when is_binary(event_id) and is_atom(broadcaster) do
    dispatch_safely(event_id, nil, broadcaster)
  end

  def dispatch(
        event_id,
        %{organization_id: organization_id, workspace_id: workspace_id} = scope
      )
      when is_binary(event_id) and is_binary(organization_id) and is_binary(workspace_id),
      do: dispatch_safely(event_id, scope, Subscriptions)

  def dispatch(_event_id, _broadcaster), do: {:error, {:terminal, :invalid_event_id}}

  defp dispatch_safely(event_id, expected_scope, broadcaster) do
    case transaction(fn -> dispatch_locked(event_id, expected_scope, broadcaster) end) do
      {:ok, result} -> result
      {:error, _error} -> {:error, {:retryable, :event_transaction_failed}}
    end
  catch
    _kind, _reason -> {:error, {:retryable, :event_dispatch_crashed}}
  end

  defp dispatch_locked(event_id, expected_scope, broadcaster) do
    case read_event_for_transition(event_id) do
      {:ok, nil} ->
        {:error, {:terminal, :event_not_found}}

      {:ok, event} ->
        if event_in_scope?(event, expected_scope) do
          dispatch_event(event, broadcaster)
        else
          {:error, {:terminal, :event_scope_mismatch}}
        end

      {:error, _error} ->
        {:error, {:retryable, :event_read_failed}}
    end
  end

  def mark_failed(event_id, failure_code) do
    mark_failed(event_id, nil, failure_code)
  end

  def mark_failed(event_id, expected_scope, failure_code) do
    failure_code =
      OfficeGraph.DurableDelivery.WorkerResult.safe_code(failure_code, "delivery_failed")

    if valid_event_id?(event_id) do
      case transaction(fn -> mark_failed_locked(event_id, expected_scope, failure_code) end) do
        {:ok, result} -> result
        {:error, _error} -> {:error, {:retryable, :event_transaction_failed}}
      end
    else
      :ok
    end
  catch
    _kind, _reason -> {:error, {:retryable, :event_failure_transition_crashed}}
  end

  defp mark_failed_locked(event_id, expected_scope, failure_code) do
    case read_event_for_transition(event_id) do
      {:ok, %{delivery_state: "pending"} = event} ->
        if event_in_scope?(event, expected_scope) do
          mark_event_failed(event, failure_code)
        else
          :ok
        end

      {:ok, _missing_or_terminal_event} ->
        :ok

      {:error, _error} ->
        {:error, {:retryable, :event_read_failed}}
    end
  end

  defp mark_event_failed(event, failure_code) do
    event
    |> Ash.Changeset.for_update(:mark_failed, %{
      delivery_state: "failed",
      failure_code: failure_code,
      failed_at: DateTime.utc_now()
    })
    |> Ash.update(return_notifications?: true)
    |> case do
      {:ok, _failed, _notifications} -> :ok
      {:error, _error} -> {:error, {:retryable, :event_update_failed}}
    end
  end

  defp record_and_enqueue_request(request) do
    with {:ok, event, insert_result} <- create_or_replay_event(request),
         :ok <- validate_replay(event, request),
         :ok <- enqueue_if_created(event, insert_result) do
      event
    else
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp create_or_replay_event(request) do
    DomainEvent
    |> Ash.Changeset.for_create(:create, EventRequest.to_attrs(request))
    |> Ash.create(
      upsert?: true,
      upsert_identity: :event_key,
      upsert_fields: [],
      touch_update_defaults?: false,
      return_notifications?: true
    )
    |> case do
      {:ok, event, _notifications} ->
        insert_result =
          case Ash.Resource.get_metadata(event, :upsert_action) do
            :update ->
              :replayed

            :insert ->
              :created

            _other ->
              if Ash.Resource.get_metadata(event, :upsert_skipped), do: :replayed, else: :created
          end

        {:ok, event, insert_result}

      result ->
        result
    end
  end

  defp validate_replay(event, request) do
    matching? =
      Enum.all?(
        [
          :event_key,
          :event_kind,
          :subject_kind,
          :subject_id,
          :subject_version,
          :organization_id,
          :workspace_id,
          :operation_id,
          :causation_event_id
        ],
        &(Map.fetch!(event, &1) == Map.fetch!(request, &1))
      )

    if matching?, do: :ok, else: {:error, :event_identity_conflict}
  end

  defp enqueue(event) do
    %{
      "event_id" => event.id,
      "organization_id" => event.organization_id,
      "workspace_id" => event.workspace_id
    }
    |> DispatchEventWorker.new()
    |> Oban.insert()
  end

  defp enqueue_if_created(event, :created) do
    case enqueue(event) do
      {:ok, _job} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  defp enqueue_if_created(_event, :replayed), do: :ok

  defp authorize_terminal_read(session_context) do
    with true <- is_map(session_context),
         :ok <- OfficeGraph.Identity.validate_session_context(session_context),
         :ok <-
           OfficeGraph.Authorization.authorize(
             session_context,
             :durable_delivery_read,
             organization_id: session_context.organization_id
           ) do
      :ok
    else
      _other -> {:error, :forbidden}
    end
  end

  defp normalize_limit(limit) when is_integer(limit), do: min(max(limit, 1), 100)
  defp normalize_limit(_limit), do: 50

  defp failure_codes_by_event(jobs) do
    event_ids =
      jobs
      |> Enum.flat_map(fn job ->
        event_id = job.args["event_id"]

        case Ecto.UUID.cast(event_id) do
          {:ok, event_id} -> [event_id]
          :error -> []
        end
      end)
      |> Enum.uniq()

    if event_ids == [] do
      %{}
    else
      DomainEvent
      |> Ash.Query.filter(id in ^event_ids)
      |> Ash.read!()
      |> Map.new(&{&1.id, &1.failure_code})
    end
  end

  defp terminal_failure_code(%Oban.Job{meta: %{"terminal_failure_code" => code}}) do
    OfficeGraph.DurableDelivery.WorkerResult.safe_code(code, nil)
  end

  defp terminal_failure_code(_job), do: nil

  defp valid_event_id?(event_id), do: match?({:ok, _event_id}, Ecto.UUID.cast(event_id))

  defp read_event_for_transition(event_id) do
    DomainEvent
    |> Ash.Query.filter(id == ^event_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one()
  end

  defp event_in_scope?(_event, nil), do: true

  defp event_in_scope?(event, expected_scope) do
    event.organization_id == expected_scope.organization_id and
      event.workspace_id == expected_scope.workspace_id
  end

  defp dispatch_event(%{delivery_state: "pending"} = event, broadcaster),
    do: dispatch_pending(event, broadcaster)

  defp dispatch_event(%{delivery_state: "dispatched"}, _broadcaster), do: :ok

  defp dispatch_event(%{delivery_state: "failed", failure_code: code}, _broadcaster),
    do: {:error, {:terminal, code || "delivery_failed"}}

  defp dispatch_pending(event, broadcaster) do
    invalidation = ProjectionInvalidation.from_event(event)

    case broadcaster.broadcast(invalidation) do
      :ok -> mark_dispatched(event)
      {:error, _error} -> {:error, {:retryable, :projection_broadcast_failed}}
      _other -> {:error, {:retryable, :projection_broadcast_failed}}
    end
  end

  defp mark_dispatched(event) do
    event
    |> Ash.Changeset.for_update(:mark_dispatched, %{
      delivery_state: "dispatched",
      dispatched_at: DateTime.utc_now(),
      failure_code: nil,
      failed_at: nil
    })
    |> Ash.update(return_notifications?: true)
    |> case do
      {:ok, _dispatched, _notifications} -> :ok
      {:error, _error} -> {:error, {:retryable, :event_update_failed}}
    end
  end

  defp transaction(fun) do
    if Repo.in_transaction?() do
      {:ok, fun.()}
    else
      Repo.transaction(fun)
    end
  end
end
