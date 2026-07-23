defmodule OfficeGraph.Projections.RunIndex do
  @moduledoc false

  alias OfficeGraph.Authorization
  alias OfficeGraph.Projections.KeysetCursor
  alias OfficeGraph.Runs.Run
  alias OfficeGraph.WorkPackets.{WorkPacket, WorkPacketVersion}

  require Ash.Query

  @default_limit 50
  @max_limit 100

  def page(session_context, opts) do
    with {:ok, limit} <- page_limit(opts),
         :ok <- authorize_read(session_context),
         {:ok, cursor} <- page_cursor(opts),
         {:ok, runs} <- read_runs(session_context, limit, cursor),
         {:ok, rows} <- build_rows(session_context, Enum.take(runs, limit)) do
      {:ok,
       %{
         row_edges: Enum.map(rows, &{&1, cursor: encode_cursor(&1)}),
         has_next_page?: length(runs) > limit,
         has_previous_page?: not is_nil(option(opts, :after_cursor, nil))
       }}
    end
  end

  defp authorize_read(session_context) do
    Authorization.authorize_projection(session_context, :skeleton_read,
      organization_id: session_context.organization_id
    )
  end

  defp read_runs(session_context, limit, cursor) do
    Run
    |> Ash.Query.filter(
      organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> apply_cursor(cursor)
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
    |> Ash.Query.limit(limit + 1)
    |> Ash.read(actor: session_context)
  end

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, %{inserted_at: inserted_at, id: id}) do
    Ash.Query.filter(
      query,
      inserted_at < ^inserted_at or (inserted_at == ^inserted_at and id < ^id)
    )
  end

  defp build_rows(_session_context, []), do: {:ok, []}

  defp build_rows(session_context, runs) do
    with {:ok, packets_by_id} <- read_packets(session_context, runs),
         {:ok, versions_by_id} <- read_packet_versions(session_context, runs) do
      runs
      |> Enum.reduce_while({:ok, []}, fn run, {:ok, rows} ->
        with {:ok, packet} <- Map.fetch(packets_by_id, run.work_packet_id),
             {:ok, packet_version} <- Map.fetch(versions_by_id, run.work_packet_version_id) do
          {:cont, {:ok, [run_row(run, packet, packet_version) | rows]}}
        else
          :error -> {:halt, {:error, :forbidden}}
        end
      end)
      |> then(fn
        {:ok, rows} -> {:ok, Enum.reverse(rows)}
        error -> error
      end)
    end
  end

  defp read_packets(session_context, runs) do
    packet_ids = Enum.map(runs, & &1.work_packet_id)

    WorkPacket
    |> Ash.Query.filter(
      id in ^packet_ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read(actor: session_context)
    |> map_by_id()
  end

  defp read_packet_versions(session_context, runs) do
    version_ids = Enum.map(runs, & &1.work_packet_version_id)

    WorkPacketVersion
    |> Ash.Query.filter(
      id in ^version_ids and organization_id == ^session_context.organization_id and
        workspace_id == ^session_context.workspace_id
    )
    |> Ash.read(actor: session_context)
    |> map_by_id()
  end

  defp map_by_id({:ok, records}), do: {:ok, Map.new(records, &{&1.id, &1})}
  defp map_by_id({:error, error}), do: {:error, error}

  defp run_row(run, packet, packet_version) do
    %{
      id: run.id,
      objective: run.objective,
      aggregate_state: run.aggregate_state,
      execution_state: run.execution_state,
      verification_state: run.verification_state,
      inserted_at: run.inserted_at,
      packet: %{id: packet.id, title: packet.title, state: packet.state},
      packet_version: %{
        id: packet_version.id,
        version_number: packet_version.version_number,
        lifecycle_state: packet_version.lifecycle_state,
        objective: packet_version.objective
      }
    }
    |> with_source_watermark()
  end

  defp with_source_watermark(row) do
    watermark =
      row
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.url_encode64(padding: false)

    Map.put(row, :source_watermark, watermark)
  end

  defp page_limit(opts) do
    case option(opts, :limit, @default_limit) do
      value when is_integer(value) and value < 0 -> {:error, {:invalid_field, :first}}
      value when is_integer(value) -> {:ok, Kernel.min(value, @max_limit)}
      _other -> {:ok, @default_limit}
    end
  end

  defp page_cursor(opts), do: decode_cursor(option(opts, :after_cursor, nil))
  defp decode_cursor(nil), do: {:ok, nil}

  defp decode_cursor(cursor) when is_binary(cursor) do
    with {:ok, [inserted_at, id]} <- KeysetCursor.decode(cursor, 2),
         {:ok, inserted_at, _offset} <- DateTime.from_iso8601(inserted_at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, %{inserted_at: inserted_at, id: id}}
    else
      _invalid -> {:error, {:invalid_field, :after_cursor}}
    end
  end

  defp decode_cursor(_cursor), do: {:error, {:invalid_field, :after_cursor}}

  defp encode_cursor(%{inserted_at: inserted_at, id: id}) do
    KeysetCursor.encode([DateTime.to_iso8601(inserted_at), id])
  end

  defp option(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)
  defp option(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
end
