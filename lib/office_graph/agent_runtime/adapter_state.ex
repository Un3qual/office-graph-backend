defmodule OfficeGraph.AgentRuntime.AdapterState do
  @moduledoc false

  use GenServer

  @retention_limit 32

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def reset(namespace), do: GenServer.call(__MODULE__, {:reset, namespace})

  def register(namespace, request_id),
    do: GenServer.call(__MODULE__, {:register, namespace, request_id})

  def claim(namespace, key, request_id, fingerprint),
    do: GenServer.call(__MODULE__, {:claim, namespace, key, request_id, fingerprint})

  def complete(namespace, key, fingerprint, result),
    do: GenServer.call(__MODULE__, {:complete, namespace, key, fingerprint, result})

  def cancel(namespace, request_id),
    do: GenServer.call(__MODULE__, {:cancel, namespace, request_id})

  def put_retained(namespace, request_id, retained),
    do: GenServer.call(__MODULE__, {:put_retained, namespace, request_id, retained})

  def retained(namespace, request_id),
    do: GenServer.call(__MODULE__, {:retained, namespace, request_id})

  def entry_count(namespace), do: GenServer.call(__MODULE__, {:entry_count, namespace})
  def retention_limit, do: @retention_limit

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:reset, namespace}, _from, state),
    do: {:reply, :ok, Map.delete(state, namespace)}

  def handle_call({:register, namespace, request_id}, _from, state) do
    runtime = runtime(state, namespace)

    runtime =
      put_in(
        runtime.requests[request_id],
        Map.get(runtime.requests, request_id, %{status: :unclaimed})
      )

    {:reply, :ok, put_runtime(state, namespace, runtime)}
  end

  def handle_call({:claim, namespace, key, request_id, fingerprint}, from, state) do
    runtime = runtime(state, namespace)

    case Map.get(runtime.requests, request_id) do
      %{status: :cancelled} ->
        {:reply, :cancelled, state}

      _request ->
        claim_entry(runtime, key, request_id, fingerprint, from, state, namespace)
    end
  end

  def handle_call({:complete, namespace, key, fingerprint, result}, _from, state) do
    runtime = runtime(state, namespace)

    case Map.get(runtime.entries, key) do
      %{status: :pending, fingerprint: ^fingerprint} = entry ->
        completed = %{entry | status: :completed, result: result, waiters: []}
        Enum.each(entry.waiters, &GenServer.reply(&1, {:replay, result}))

        runtime = %{
          runtime
          | entries: Map.put(runtime.entries, key, completed),
            order: [key | runtime.order]
        }

        runtime = put_in(runtime.requests[entry.request_id], %{status: :completed, key: key})
        runtime = prune(runtime)
        {:reply, {:completed, result}, put_runtime(state, namespace, runtime)}

      %{status: :cancelled} ->
        {:reply, :cancelled, state}

      %{status: :completed, fingerprint: ^fingerprint, result: completed_result} ->
        {:reply, {:replay, completed_result}, state}

      _entry ->
        {:reply, :conflict, state}
    end
  end

  def handle_call({:cancel, namespace, request_id}, _from, state) do
    runtime = runtime(state, namespace)

    case Map.get(runtime.requests, request_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :completed} ->
        {:reply, :ok, state}

      %{status: :cancelled} ->
        {:reply, :ok, state}

      %{status: :pending, key: key} ->
        entry = Map.fetch!(runtime.entries, key)
        Enum.each(entry.waiters, &GenServer.reply(&1, :cancelled))
        cancelled = %{entry | status: :cancelled, result: nil, waiters: []}

        runtime = %{
          runtime
          | entries: Map.put(runtime.entries, key, cancelled),
            order: [key | runtime.order]
        }

        runtime = put_in(runtime.requests[request_id], %{status: :cancelled, key: key})
        runtime = prune(runtime)
        {:reply, :ok, put_runtime(state, namespace, runtime)}

      %{status: :unclaimed} ->
        runtime = put_in(runtime.requests[request_id], %{status: :cancelled})
        {:reply, :ok, put_runtime(state, namespace, runtime)}
    end
  end

  def handle_call({:put_retained, namespace, request_id, retained}, _from, state) do
    runtime = runtime(state, namespace)

    if Map.has_key?(runtime.requests, request_id) do
      runtime = put_in(runtime.retained[request_id], retained)
      {:reply, :ok, put_runtime(state, namespace, runtime)}
    else
      {:reply, :ok, state}
    end
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

  defp claim_entry(runtime, key, request_id, fingerprint, from, state, namespace) do
    case Map.get(runtime.entries, key) do
      nil ->
        entry = %{
          status: :pending,
          fingerprint: fingerprint,
          request_id: request_id,
          result: nil,
          waiters: []
        }

        runtime = put_in(runtime.entries[key], entry)
        runtime = put_in(runtime.requests[request_id], %{status: :pending, key: key})
        {:reply, :claimed, put_runtime(state, namespace, runtime)}

      %{fingerprint: ^fingerprint, status: :completed, result: result} ->
        {:reply, {:replay, result}, state}

      %{fingerprint: ^fingerprint, status: :cancelled} ->
        {:reply, :cancelled, state}

      %{fingerprint: ^fingerprint, status: :pending} = entry ->
        runtime = put_in(runtime.entries[key], %{entry | waiters: [from | entry.waiters]})
        {:noreply, put_runtime(state, namespace, runtime)}

      _entry ->
        {:reply, :conflict, state}
    end
  end

  defp prune(runtime) do
    if map_size(runtime.entries) <= @retention_limit do
      runtime
    else
      key = List.last(runtime.order)
      order = List.delete_at(runtime.order, -1)
      entry = Map.fetch!(runtime.entries, key)
      runtime = %{runtime | entries: Map.delete(runtime.entries, key), order: order}

      runtime =
        if get_in(runtime, [:requests, entry.request_id, :key]) == key do
          %{
            runtime
            | requests: Map.delete(runtime.requests, entry.request_id),
              retained: Map.delete(runtime.retained, entry.request_id)
          }
        else
          runtime
        end

      prune(runtime)
    end
  end

  defp runtime(state, namespace),
    do: Map.get(state, namespace, %{entries: %{}, requests: %{}, retained: %{}, order: []})

  defp put_runtime(state, namespace, runtime), do: Map.put(state, namespace, runtime)
end
