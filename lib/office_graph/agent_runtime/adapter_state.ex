defmodule OfficeGraph.AgentRuntime.AdapterState do
  @moduledoc """
  Coordinates bounded, in-VM replay claims for read-only adapter calls.

  This process deliberately does not provide cross-restart durability. Durable
  execution steps own persisted outcomes and retry recovery; this state only
  prevents duplicate work among callers in the current runtime. Adapter
  contracts enforce a no-external-write posture while this ephemeral
  coordinator is in use.
  """

  use GenServer

  defmodule Entry do
    @moduledoc false

    @enforce_keys [:fingerprint, :status]
    defstruct [:fingerprint, :result, :status]
  end

  @default_retention_limit 32

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def reset(namespace), do: GenServer.call(__MODULE__, {:reset, namespace})

  def register(namespace, request_id),
    do: GenServer.call(__MODULE__, {:register, namespace, request_id})

  def claim(namespace, key, request_id, fingerprint),
    do: claim(namespace, key, request_id, fingerprint, :infinity)

  def claim(namespace, key, request_id, fingerprint, :infinity) do
    claim_ref = make_ref()

    GenServer.call(
      __MODULE__,
      {:claim, namespace, key, request_id, fingerprint, claim_ref},
      :infinity
    )
  end

  def claim(namespace, key, request_id, fingerprint, timeout)
      when is_integer(timeout) and timeout > 0 do
    claim_ref = make_ref()

    try do
      GenServer.call(
        __MODULE__,
        {:claim, namespace, key, request_id, fingerprint, claim_ref},
        timeout
      )
    catch
      :exit, {:timeout, _call} ->
        GenServer.call(
          __MODULE__,
          {:expire_claim, namespace, key, request_id, fingerprint, claim_ref},
          :infinity
        )
    end
  end

  def complete(namespace, key, fingerprint, result),
    do: GenServer.call(__MODULE__, {:complete, namespace, key, fingerprint, result})

  def cancel(namespace, request_id),
    do: GenServer.call(__MODULE__, {:cancel, namespace, request_id})

  def put_retained(namespace, request_id, retained),
    do: GenServer.call(__MODULE__, {:put_retained, namespace, request_id, retained})

  def retained(namespace, request_id),
    do: GenServer.call(__MODULE__, {:retained, namespace, request_id})

  def entry_count(namespace), do: GenServer.call(__MODULE__, {:entry_count, namespace})
  def state_counts(namespace), do: GenServer.call(__MODULE__, {:state_counts, namespace})

  def retention_limit do
    case Application.get_env(
           :office_graph,
           :agent_runtime_retention_limit,
           @default_retention_limit
         ) do
      limit when is_integer(limit) and limit > 0 -> limit
      _invalid -> @default_retention_limit
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:reset, namespace}, _from, state) do
    runtime = runtime(state, namespace)

    Enum.each(runtime.pending, fn {_key, pending} ->
      Enum.each(pending.waiters, &reply_waiter(&1, :cancelled))
      demonitor_pending(pending)
    end)

    {:reply, :ok, Map.delete(state, namespace)}
  end

  def handle_call({:register, namespace, request_id}, _from, state) do
    runtime = runtime(state, namespace)

    runtime =
      if active_request?(runtime, request_id) or Map.has_key?(runtime.requests, request_id) do
        runtime
      else
        put_record(runtime, request_id, %{status: :unclaimed})
      end

    {:reply, :ok, put_runtime(state, namespace, runtime)}
  end

  def handle_call({:claim, namespace, key, request_id, fingerprint, claim_ref}, from, state) do
    runtime = runtime(state, namespace)

    case Map.get(runtime.requests, request_id) do
      %{status: :cancelled} ->
        {:reply, :cancelled, state}

      %{status: :timed_out} ->
        {:reply, timeout_error(), state}

      _record ->
        case request_binding(runtime, request_id) do
          {:bound, ^key, ^fingerprint} ->
            claim_bound_request(
              runtime,
              key,
              request_id,
              fingerprint,
              claim_ref,
              from,
              state,
              namespace
            )

          {:bound, _bound_key, _bound_fingerprint} ->
            {:reply, :identity_conflict, state}

          :unbound ->
            claim_bound_request(
              runtime,
              key,
              request_id,
              fingerprint,
              claim_ref,
              from,
              state,
              namespace
            )
        end
    end
  end

  def handle_call(
        {:expire_claim, namespace, key, request_id, fingerprint, claim_ref},
        _from,
        state
      ) do
    runtime = runtime(state, namespace)
    runtime = expire_claim(runtime, key, request_id, fingerprint, claim_ref)
    {:reply, timeout_error(), put_runtime(state, namespace, runtime)}
  end

  def handle_call({:complete, namespace, key, fingerprint, result}, from, state) do
    runtime = runtime(state, namespace)
    caller = caller_pid(from)

    case Map.get(runtime.pending, key) do
      %{fingerprint: ^fingerprint, owner: ^caller} = pending ->
        Enum.each(pending.waiters, &reply_waiter(&1, {:replay, result}))
        demonitor_pending(pending)

        runtime = %{runtime | pending: Map.delete(runtime.pending, key)}

        runtime =
          if retryable_result?(result) do
            retryable = %Entry{fingerprint: fingerprint, result: nil, status: :retryable}

            runtime
            |> then(&%{&1 | entries: Map.put(&1.entries, key, retryable)})
            |> put_record(pending.request_id, request_record(:retryable, key, fingerprint))
            |> record_retryable_waiters(
              pending.waiters,
              pending.request_id,
              key,
              fingerprint
            )
          else
            completed = %Entry{
              fingerprint: fingerprint,
              result: result,
              status: :completed
            }

            runtime = %{runtime | entries: Map.put(runtime.entries, key, completed)}

            runtime =
              put_record(
                runtime,
                pending.request_id,
                request_record(:completed, key, fingerprint)
              )

            Enum.reduce(pending.waiters, runtime, fn waiter, current ->
              record_replay(current, waiter.request_id, key, fingerprint, waiter.claim_ref)
            end)
          end

        {:reply, {:completed, result}, put_runtime(state, namespace, runtime)}

      %{fingerprint: ^fingerprint} ->
        {:reply, :conflict, state}

      _pending ->
        case Map.get(runtime.entries, key) do
          %Entry{fingerprint: ^fingerprint, status: :completed, result: completed_result} ->
            {:reply, {:replay, completed_result}, state}

          %Entry{fingerprint: ^fingerprint, status: :cancelled} ->
            {:reply, :cancelled, state}

          _entry ->
            {:reply, :conflict, state}
        end
    end
  end

  def handle_call({:cancel, namespace, request_id}, _from, state) do
    runtime = runtime(state, namespace)

    case pending_request(runtime, request_id) do
      {:owner, key, pending} ->
        runtime = cancel_pending(runtime, key, pending)
        {:reply, :ok, put_runtime(state, namespace, runtime)}

      {:waiter, key, pending, waiter} ->
        GenServer.reply(waiter.from, :cancelled)
        Process.demonitor(waiter.monitor, [:flush])
        remaining_waiters = List.delete(pending.waiters, waiter)
        runtime = put_in(runtime.pending[key].waiters, remaining_waiters)
        runtime = terminalize_request(runtime, request_id, :cancelled, key, pending.fingerprint)
        {:reply, :ok, put_runtime(state, namespace, runtime)}

      :none ->
        case Map.get(runtime.requests, request_id) do
          nil ->
            {:reply, {:error, :not_found}, state}

          %{status: status} when status in [:completed, :conflict, :replayed, :timed_out] ->
            {:reply, :ok, state}

          %{status: :cancelled} ->
            {:reply, :ok, state}

          %{status: status, replay_key: key, fingerprint: fingerprint}
          when status in [:retryable, :abandoned] ->
            runtime = cancel_restartable(runtime, request_id, key, fingerprint)
            {:reply, :ok, put_runtime(state, namespace, runtime)}

          _record ->
            runtime = terminalize_request(runtime, request_id, :cancelled)
            {:reply, :ok, put_runtime(state, namespace, runtime)}
        end
    end
  end

  def handle_call({:put_retained, namespace, request_id, retained}, _from, state) do
    runtime = runtime(state, namespace)

    runtime =
      case Map.get(runtime.requests, request_id) do
        %{status: status}
        when status in [:completed, :cancelled, :conflict, :replayed, :retryable, :timed_out] ->
          %{
            runtime
            | retained: put_retained_metadata(runtime.retained, request_id, retained)
          }

        _record ->
          runtime
      end

    {:reply, :ok, put_runtime(state, namespace, runtime)}
  end

  def handle_call({:retained, namespace, request_id}, _from, state) do
    runtime = runtime(state, namespace)

    case Map.fetch(runtime.retained, request_id) do
      {:ok, retained} -> {:reply, {:ok, retained}, state}
      :error -> {:reply, :error, state}
    end
  end

  def handle_call({:entry_count, namespace}, _from, state) do
    {:reply, map_size(runtime(state, namespace).entries), state}
  end

  def handle_call({:state_counts, namespace}, _from, state) do
    runtime = runtime(state, namespace)

    {:reply,
     %{
       pending: map_size(runtime.pending),
       terminal: map_size(runtime.entries),
       records: map_size(runtime.requests),
       retained: map_size(runtime.retained),
       waiters: waiter_count(runtime),
       total:
         map_size(runtime.pending) + waiter_count(runtime) + map_size(runtime.entries) +
           map_size(runtime.requests) + map_size(runtime.retained)
     }, state}
  end

  defp claim_bound_request(
         runtime,
         key,
         request_id,
         fingerprint,
         claim_ref,
         from,
         state,
         namespace
       ) do
    case Map.get(runtime.pending, key) do
      nil ->
        claim_terminal_or_new(
          runtime,
          key,
          request_id,
          fingerprint,
          claim_ref,
          from,
          state,
          namespace
        )

      %{fingerprint: ^fingerprint} = pending ->
        runtime = add_waiter(runtime, key, pending, request_id, claim_ref, from)
        {:noreply, put_runtime(state, namespace, runtime)}

      _pending ->
        runtime = terminalize_request(runtime, request_id, :conflict, key, fingerprint)
        {:reply, :conflict, put_runtime(state, namespace, runtime)}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    {namespace, key, pending, role} = pending_monitor(state, monitor)

    case role do
      :owner ->
        runtime = runtime(state, namespace)
        runtime = recover_owner(runtime, key, pending)
        {:noreply, put_runtime(state, namespace, runtime)}

      {:waiter, waiter} ->
        runtime = runtime(state, namespace)
        runtime = put_in(runtime.pending[key].waiters, List.delete(pending.waiters, waiter))
        {:noreply, put_runtime(state, namespace, runtime)}

      :none ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp claim_terminal_or_new(
         runtime,
         key,
         request_id,
         fingerprint,
         claim_ref,
         from,
         state,
         namespace
       ) do
    case Map.get(runtime.entries, key) do
      %Entry{fingerprint: ^fingerprint, status: :completed, result: result} ->
        runtime = record_replay(runtime, request_id, key, fingerprint, claim_ref)
        {:reply, {:replay, result}, put_runtime(state, namespace, runtime)}

      %Entry{fingerprint: ^fingerprint, status: :cancelled} ->
        runtime = terminalize_request(runtime, request_id, :cancelled, key, fingerprint)
        {:reply, :cancelled, put_runtime(state, namespace, runtime)}

      %Entry{fingerprint: ^fingerprint, status: :timed_out} ->
        runtime = terminalize_request(runtime, request_id, :timed_out, key, fingerprint)
        {:reply, timeout_error(), put_runtime(state, namespace, runtime)}

      %Entry{fingerprint: ^fingerprint, status: :abandoned} ->
        start_claim(runtime, key, request_id, fingerprint, claim_ref, from, state, namespace)

      %Entry{fingerprint: ^fingerprint, status: :retryable} ->
        start_claim(runtime, key, request_id, fingerprint, claim_ref, from, state, namespace)

      %Entry{} ->
        runtime = terminalize_request(runtime, request_id, :conflict, key, fingerprint)
        {:reply, :conflict, put_runtime(state, namespace, runtime)}

      nil ->
        start_claim(runtime, key, request_id, fingerprint, claim_ref, from, state, namespace)
    end
  end

  defp start_claim(
         runtime,
         key,
         request_id,
         fingerprint,
         claim_ref,
         from,
         state,
         namespace
       ) do
    case Map.get(runtime.requests, request_id) do
      %{status: :cancelled} ->
        {:reply, :cancelled, state}

      _record ->
        {owner, owner_monitor} = monitor_caller(from)

        pending = %{
          fingerprint: fingerprint,
          owner: owner,
          owner_claim_ref: claim_ref,
          owner_monitor: owner_monitor,
          request_id: request_id,
          waiters: []
        }

        runtime = %{
          runtime
          | pending: Map.put(runtime.pending, key, pending),
            requests: Map.delete(runtime.requests, request_id),
            order: List.delete(runtime.order, request_id)
        }

        {:reply, :claimed, put_runtime(state, namespace, runtime)}
    end
  end

  defp add_waiter(runtime, key, pending, request_id, claim_ref, from) do
    {pid, monitor} = monitor_caller(from)

    waiter = %{
      claim_ref: claim_ref,
      from: from,
      monitor: monitor,
      pid: pid,
      request_id: request_id
    }

    runtime = %{
      runtime
      | requests: Map.delete(runtime.requests, request_id),
        order: List.delete(runtime.order, request_id)
    }

    put_in(runtime.pending[key].waiters, [waiter | pending.waiters])
  end

  defp expire_claim(runtime, key, request_id, fingerprint, claim_ref) do
    case pending_claim(runtime, request_id, claim_ref) do
      {:waiter, ^key, %{fingerprint: ^fingerprint} = pending, waiter} ->
        Process.demonitor(waiter.monitor, [:flush])
        remaining_waiters = List.delete(pending.waiters, waiter)
        runtime = put_in(runtime.pending[key].waiters, remaining_waiters)

        if pending.request_id == request_id do
          runtime
        else
          terminalize_request(runtime, request_id, :timed_out, key, fingerprint)
        end

      {:owner, ^key, %{fingerprint: ^fingerprint} = pending} ->
        Process.demonitor(pending.owner_monitor, [:flush])
        expire_owner_claim(runtime, key, pending)

      _not_pending ->
        terminalize_timed_out_delivery(runtime, key, request_id, fingerprint, claim_ref)
    end
  end

  defp expire_owner_claim(runtime, key, pending) do
    runtime =
      case pending.waiters do
        [waiter | remaining_waiters] ->
          GenServer.reply(waiter.from, :claimed)

          promoted = %{
            pending
            | owner: waiter.pid,
              owner_claim_ref: waiter.claim_ref,
              owner_monitor: waiter.monitor,
              request_id: waiter.request_id,
              waiters: remaining_waiters
          }

          put_in(runtime.pending[key], promoted)

        [] ->
          runtime
          |> then(&%{&1 | pending: Map.delete(&1.pending, key)})
          |> put_entry(key, pending.fingerprint, :timed_out)
      end

    terminalize_request(
      runtime,
      pending.request_id,
      :timed_out,
      key,
      pending.fingerprint
    )
  end

  defp terminalize_timed_out_delivery(runtime, key, request_id, fingerprint, claim_ref) do
    case Map.get(runtime.requests, request_id) do
      %{status: status, replay_key: ^key, fingerprint: ^fingerprint, claim_ref: ^claim_ref}
      when status in [:replayed, :retryable] ->
        terminalize_request(runtime, request_id, :timed_out, key, fingerprint)

      _record ->
        runtime
    end
  end

  defp cancel_pending(runtime, key, pending) do
    Enum.each(pending.waiters, &reply_waiter(&1, :cancelled))
    demonitor_pending(pending)

    cancelled = %Entry{
      fingerprint: pending.fingerprint,
      result: nil,
      status: :cancelled
    }

    runtime = %{
      runtime
      | pending: Map.delete(runtime.pending, key),
        entries: Map.put(runtime.entries, key, cancelled)
    }

    runtime =
      put_record(
        runtime,
        pending.request_id,
        request_record(:cancelled, key, pending.fingerprint)
      )

    Enum.reduce(pending.waiters, runtime, fn waiter, current ->
      terminalize_request(current, waiter.request_id, :cancelled, key, pending.fingerprint)
    end)
  end

  defp cancel_restartable(runtime, request_id, key, fingerprint) do
    case Map.get(runtime.entries, key) do
      %Entry{fingerprint: ^fingerprint, status: :completed} ->
        runtime

      _restartable_entry ->
        runtime =
          case {Map.get(runtime.pending, key), Map.get(runtime.entries, key)} do
            {%{fingerprint: ^fingerprint} = pending, _entry} ->
              cancel_pending(runtime, key, pending)

            {_pending, %Entry{fingerprint: ^fingerprint, status: status}}
            when status in [:retryable, :abandoned] ->
              put_entry(runtime, key, fingerprint, :cancelled)

            _state ->
              runtime
          end

        terminalize_request(runtime, request_id, :cancelled, key, fingerprint)
    end
  end

  defp recover_owner(runtime, key, pending) do
    case pending.waiters do
      [waiter | remaining_waiters] ->
        GenServer.reply(waiter.from, :claimed)

        promoted = %{
          pending
          | owner: waiter.pid,
            owner_claim_ref: waiter.claim_ref,
            owner_monitor: waiter.monitor,
            request_id: waiter.request_id,
            waiters: remaining_waiters
        }

        runtime = put_in(runtime.pending[key], promoted)
        terminalize_request(runtime, pending.request_id, :abandoned, key, pending.fingerprint)

      [] ->
        runtime =
          runtime
          |> then(&%{&1 | pending: Map.delete(&1.pending, key)})
          |> put_entry(key, pending.fingerprint, :abandoned)

        terminalize_request(runtime, pending.request_id, :abandoned, key, pending.fingerprint)
    end
  end

  defp put_entry(runtime, key, fingerprint, status) do
    entry = %Entry{fingerprint: fingerprint, result: nil, status: status}
    %{runtime | entries: Map.put(runtime.entries, key, entry)}
  end

  defp terminalize_request(runtime, request_id, status, replay_key \\ nil, fingerprint \\ nil) do
    existing = Map.get(runtime.requests, request_id, %{})

    record =
      %{status: status}
      |> preserve_binding(existing, :replay_key)
      |> preserve_binding(existing, :fingerprint)
      |> bind(:replay_key, replay_key)
      |> bind(:fingerprint, fingerprint)

    put_record(runtime, request_id, record)
  end

  defp record_replay(runtime, request_id, key, fingerprint, claim_ref) do
    existing = Map.get(runtime.requests, request_id)

    record =
      if successful_record?(existing, key, fingerprint),
        do: existing,
        else: request_record(:replayed, key, fingerprint, claim_ref)

    put_record(runtime, request_id, record)
  end

  defp successful_record?(record, key, fingerprint) do
    Map.get(record || %{}, :status) in [:completed, :replayed] and
      Map.get(record || %{}, :replay_key) == key and
      Map.get(record || %{}, :fingerprint) == fingerprint
  end

  defp request_record(status, replay_key, fingerprint, claim_ref \\ nil) do
    %{status: status, replay_key: replay_key, fingerprint: fingerprint}
    |> bind(:claim_ref, claim_ref)
  end

  defp put_record(runtime, request_id, record) do
    runtime = %{
      runtime
      | requests: Map.put(runtime.requests, request_id, record),
        order: [request_id | List.delete(runtime.order, request_id)]
    }

    prune(runtime)
  end

  defp prune(runtime) do
    if map_size(runtime.requests) <= retention_limit() do
      runtime
    else
      request_id = List.last(runtime.order)
      record = Map.fetch!(runtime.requests, request_id)

      runtime =
        %{
          runtime
          | requests: Map.delete(runtime.requests, request_id),
            retained: Map.delete(runtime.retained, request_id),
            order: List.delete(runtime.order, request_id)
        }
        |> prune_unreferenced_entry(record)

      prune(runtime)
    end
  end

  defp prune_unreferenced_entry(runtime, %{status: status, replay_key: replay_key})
       when status in [
              :completed,
              :conflict,
              :replayed,
              :cancelled,
              :retryable,
              :timed_out,
              :abandoned
            ] do
    if Map.has_key?(runtime.pending, replay_key) or
         Enum.any?(runtime.requests, fn {_request_id, record} ->
           entry_reference?(record, replay_key)
         end) do
      runtime
    else
      %{runtime | entries: Map.delete(runtime.entries, replay_key)}
    end
  end

  defp prune_unreferenced_entry(runtime, _record), do: runtime

  defp entry_reference?(%{status: status, replay_key: replay_key}, replay_key)
       when status in [
              :completed,
              :conflict,
              :replayed,
              :cancelled,
              :retryable,
              :timed_out,
              :abandoned
            ],
       do: true

  defp entry_reference?(_record, _replay_key), do: false

  defp record_retryable_waiters(runtime, waiters, owner_request_id, key, fingerprint) do
    Enum.reduce(waiters, runtime, fn waiter, current ->
      if waiter.request_id == owner_request_id do
        current
      else
        put_record(
          current,
          waiter.request_id,
          request_record(:retryable, key, fingerprint, waiter.claim_ref)
        )
      end
    end)
  end

  defp retryable_result?({:error, {:retryable, _failure_code}}), do: true
  defp retryable_result?(_result), do: false
  defp timeout_error, do: {:error, {:terminal, :timeout_exceeded}}

  defp pending_request(runtime, request_id) do
    Enum.find_value(runtime.pending, :none, fn {key, pending} ->
      cond do
        pending.request_id == request_id ->
          {:owner, key, pending}

        waiter = Enum.find(pending.waiters, &(&1.request_id == request_id)) ->
          {:waiter, key, pending, waiter}

        true ->
          false
      end
    end)
  end

  defp pending_claim(runtime, request_id, claim_ref) do
    Enum.find_value(runtime.pending, :none, fn {key, pending} ->
      cond do
        pending.request_id == request_id and pending.owner_claim_ref == claim_ref ->
          {:owner, key, pending}

        waiter =
            Enum.find(
              pending.waiters,
              &(&1.request_id == request_id and &1.claim_ref == claim_ref)
            ) ->
          {:waiter, key, pending, waiter}

        true ->
          false
      end
    end)
  end

  defp active_request?(runtime, request_id), do: pending_request(runtime, request_id) != :none

  defp request_binding(runtime, request_id) do
    case pending_request(runtime, request_id) do
      {:owner, key, pending} ->
        {:bound, key, pending.fingerprint}

      {:waiter, key, pending, _waiter} ->
        {:bound, key, pending.fingerprint}

      :none ->
        case Map.get(runtime.requests, request_id) do
          %{replay_key: replay_key, fingerprint: fingerprint} ->
            {:bound, replay_key, fingerprint}

          _record ->
            :unbound
        end
    end
  end

  defp waiter_count(runtime) do
    Enum.reduce(runtime.pending, 0, fn {_key, pending}, count ->
      count + length(pending.waiters)
    end)
  end

  defp pending_monitor(state, monitor) do
    Enum.find_value(state, {nil, nil, nil, :none}, fn {namespace, runtime} ->
      Enum.find_value(runtime.pending, fn {key, pending} ->
        cond do
          pending.owner_monitor == monitor ->
            {namespace, key, pending, :owner}

          waiter = Enum.find(pending.waiters, &(&1.monitor == monitor)) ->
            {namespace, key, pending, {:waiter, waiter}}

          true ->
            false
        end
      end)
    end)
  end

  defp monitor_caller(from) do
    pid = caller_pid(from)
    {pid, Process.monitor(pid)}
  end

  defp caller_pid({pid, _tag}), do: pid
  defp reply_waiter(waiter, result), do: GenServer.reply(waiter.from, result)

  defp demonitor_pending(pending) do
    Process.demonitor(pending.owner_monitor, [:flush])
    Enum.each(pending.waiters, &Process.demonitor(&1.monitor, [:flush]))
  end

  defp preserve_binding(record, existing, field) do
    case Map.fetch(existing, field) do
      {:ok, value} -> Map.put(record, field, value)
      :error -> record
    end
  end

  defp bind(record, _field, nil), do: record
  defp bind(record, field, value), do: Map.put(record, field, value)

  defp put_retained_metadata(retained_by_request, request_id, retained) do
    Map.update(retained_by_request, request_id, retained, fn existing ->
      if match?(%{classification: :retryable}, existing), do: retained, else: existing
    end)
  end

  defp runtime(state, namespace) do
    Map.get(state, namespace, %{
      entries: %{},
      order: [],
      pending: %{},
      requests: %{},
      retained: %{}
    })
  end

  defp put_runtime(state, namespace, runtime), do: Map.put(state, namespace, runtime)
end
