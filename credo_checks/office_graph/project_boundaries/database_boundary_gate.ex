defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryGate do
  @moduledoc """
  Requires every detected database-access occurrence to match an explicitly
  approved exception.
  """

  @locator_fields ["path", "class", "construct", "function", "ordinal"]
  @approved_metadata_fields [
    "approving_change",
    "owner",
    "reason",
    "retirement_condition",
    "verification"
  ]

  alias OfficeGraph.ProjectQuality.DatabaseBoundaryScanner

  @spec compare([map()], [map()]) :: [map()]
  def compare(current, approved_exceptions) do
    current = Enum.map(current, &normalize_entry/1)

    approved_exceptions =
      Enum.map(approved_exceptions, &normalize_entry(&1, :approved_exceptions))

    case inventory_errors(approved_exceptions) do
      [] ->
        current_diagnostics(current, approved_exceptions) ++
          stale_diagnostics(current, approved_exceptions)

      errors ->
        errors
    end
  end

  @spec check_repository(Path.t()) :: [map()]
  def check_repository(root \\ File.cwd!()) do
    approved_path =
      Path.join(
        root,
        "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json"
      )

    compare(
      DatabaseBoundaryScanner.scan_repository(root),
      load_approved_inventory!(approved_path)
    )
  end

  @spec load_approved_inventory!(Path.t()) :: [map()]
  def load_approved_inventory!(path) do
    case path |> File.read!() |> Jason.decode!() do
      %{"version" => 1, "exceptions" => exceptions} when is_list(exceptions) -> exceptions
      _inventory -> raise ArgumentError, "invalid approved database exception inventory schema"
    end
  end

  defp current_diagnostics(current, approved_exceptions) do
    Enum.flat_map(current, fn occurrence ->
      case approved_match(approved_exceptions, occurrence) do
        :exact ->
          []

        {:changed, approved_exception} ->
          [
            occurrence
            |> diagnostic(:changed)
            |> Map.put(:recorded_fingerprint, approved_exception["fingerprint"])
          ]

        :new ->
          [diagnostic(occurrence, :new)]
      end
    end)
  end

  defp approved_match(approved_exceptions, occurrence) do
    Enum.reduce_while(approved_exceptions, :new, fn approved_exception, match ->
      cond do
        approved_exception["fingerprint"] == occurrence["fingerprint"] ->
          {:halt, :exact}

        same_locator?(approved_exception, occurrence) ->
          {:cont, {:changed, approved_exception}}

        true ->
          {:cont, match}
      end
    end)
  end

  defp stale_diagnostics(current, approved_exceptions) do
    approved_exceptions
    |> Enum.reject(fn approved_exception ->
      Enum.any?(current, &same_locator?(&1, approved_exception))
    end)
    |> Enum.map(fn approved_exception ->
      approved_exception
      |> diagnostic(:stale)
      |> Map.put(:inventory, :approved_exceptions)
    end)
  end

  defp inventory_errors(approved_exceptions) do
    required_fields =
      ["class", "construct", "fingerprint", "ordinal", "path"] ++
        @approved_metadata_fields

    metadata_errors =
      approved_exceptions
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {entry, index} ->
        missing_fields =
          required_fields
          |> Enum.filter(&blank?(Map.get(entry, &1)))
          |> Enum.sort()

        if missing_fields == [] do
          []
        else
          [
            %{
              kind: :invalid_inventory,
              inventory: :approved_exceptions,
              entry: index,
              missing_fields: missing_fields
            }
          ]
        end
      end)

    metadata_errors ++ duplicate_locator_errors(approved_exceptions)
  end

  defp duplicate_locator_errors(approved_exceptions) do
    approved_exceptions
    |> Enum.with_index(1)
    |> Enum.group_by(fn {entry, _index} ->
      Enum.map(@locator_fields, &Map.get(entry, &1))
    end)
    |> Map.values()
    |> Enum.filter(&(length(&1) > 1))
    |> Enum.sort_by(fn entries -> entries |> hd() |> elem(1) end)
    |> Enum.map(fn entries ->
      {entry, _index} = hd(entries)

      %{
        kind: :invalid_inventory,
        inventory: :approved_exceptions,
        entries: Enum.map(entries, &elem(&1, 1)),
        duplicate_locator: %{
          path: entry["path"],
          class: entry["class"],
          construct: entry["construct"],
          function: entry["function"],
          ordinal: entry["ordinal"]
        }
      }
    end)
  end

  defp normalize_entry(entry) do
    entry
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.update("class", nil, &to_string/1)
  end

  defp normalize_entry(entry, inventory) do
    entry
    |> normalize_entry()
    |> Map.put("inventory", inventory)
  end

  defp same_locator?(left, right) do
    Enum.all?(@locator_fields, &(Map.get(left, &1) == Map.get(right, &1)))
  end

  defp diagnostic(occurrence, kind) do
    %{
      kind: kind,
      class: occurrence["class"],
      construct: occurrence["construct"],
      fingerprint: occurrence["fingerprint"],
      function: occurrence["function"],
      line: occurrence["line"],
      ordinal: occurrence["ordinal"],
      path: occurrence["path"]
    }
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
