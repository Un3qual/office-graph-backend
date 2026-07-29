defmodule OfficeGraph.Repo do
  use Boundary, top_level?: true, deps: [], exports: []

  @dialyzer {:nowarn_function, all_tenants: 0}

  use AshPostgres.Repo,
    otp_app: :office_graph,
    warn_on_missing_ash_functions?: false

  def min_pg_version, do: %Version{major: 18, minor: 0, patch: 0}

  def ash_create!(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> unwrap_ash_write!()
  end

  def ash_bulk_create!(_resource, []), do: []

  def ash_bulk_create!(resource, inputs) do
    input_ids = Enum.map(inputs, &Map.get(&1, :id))

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
        if Enum.all?(input_ids, &is_binary/1) do
          records_by_id = Map.new(records, &{&1.id, &1})
          Enum.map(input_ids, &Map.fetch!(records_by_id, &1))
        else
          records
        end

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

  defp unwrap_ash_write!({:ok, record, _notifications}), do: record
  defp unwrap_ash_write!({:ok, record}), do: record
  defp unwrap_ash_write!({:error, error}), do: rollback(error)
end
