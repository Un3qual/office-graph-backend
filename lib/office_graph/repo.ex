defmodule OfficeGraph.Repo do
  use Boundary, top_level?: true, deps: [], exports: []

  @dialyzer {:nowarn_function, all_tenants: 0}

  use AshPostgres.Repo,
    otp_app: :office_graph,
    warn_on_missing_ash_functions?: false

  def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}

  def ash_create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> unwrap_ash_write!()
  end

  def ash_bulk_create!(_resource, []), do: []

  def ash_bulk_create!(resource, inputs) do
    input_ids = Enum.map(inputs, &Map.fetch!(&1, :id))

    case Ash.bulk_create(inputs, resource, :create,
           authorize?: false,
           return_errors?: true,
           return_notifications?: true,
           return_records?: true,
           sorted?: true,
           stop_on_error?: true,
           transaction: false
         ) do
      %Ash.BulkResult{status: :success, records: records} ->
        records_by_id = Map.new(records, &{&1.id, &1})
        Enum.map(input_ids, &Map.fetch!(records_by_id, &1))

      %Ash.BulkResult{errors: errors} when is_list(errors) and errors != [] ->
        errors
        |> Ash.Error.to_error_class()
        |> rollback()

      %Ash.BulkResult{status: status} ->
        rollback({:ash_bulk_create_failed, resource, status})
    end
  end

  def ash_update!(changeset) do
    changeset
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> unwrap_ash_write!()
  end

  def get_or_insert!(resource, lookup, attrs, insert_contract, fetch \\ &fetch_by_lookup/2) do
    case fetch.(resource, lookup) do
      {:ok, nil} ->
        attrs =
          attrs
          |> Map.new()
          |> Map.put_new(:id, Ecto.UUID.generate())

        insert_then_fetch!(resource, lookup, attrs, insert_contract, fetch)

      {:ok, record} ->
        record

      {:error, error} ->
        raise error
    end
  end

  defp insert_then_fetch!(resource, lookup, attrs, insert_contract, fetch) do
    {table, conflict_target, uuid_fields} = insert_contract.(resource, attrs)
    now = DateTime.utc_now()

    insert_attrs =
      attrs
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)
      |> dump_uuid_fields(uuid_fields)

    OfficeGraph.Repo.insert_all(table, [insert_attrs],
      on_conflict: :nothing,
      conflict_target: conflict_target
    )

    case fetch.(resource, lookup) do
      {:ok, nil} -> raise "#{inspect(resource)} not found after create"
      {:ok, record} -> record
      {:error, error} -> raise error
    end
  end

  defp fetch_by_lookup(resource, lookup) do
    Ash.get(resource, Map.new(lookup), authorize?: false, not_found_error?: false)
  end

  defp dump_uuid_fields(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc ->
      Map.update!(acc, field, fn
        nil -> nil
        value -> Ecto.UUID.dump!(value)
      end)
    end)
  end

  defp unwrap_ash_write!({:ok, record, _notifications}), do: record
  defp unwrap_ash_write!({:ok, record}), do: record
  defp unwrap_ash_write!({:error, error}), do: rollback(error)
end
