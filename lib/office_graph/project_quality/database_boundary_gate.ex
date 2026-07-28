defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryGate do
  @moduledoc """
  Compares the current database-access scan with removal-debt and explicitly
  approved exception inventories.
  """

  @locator_fields ["path", "class", "construct", "function", "ordinal"]
  @debt_metadata_fields ["owner", "remediation_change"]

  @approved_metadata_fields [
    "approving_change",
    "owner",
    "reason",
    "retirement_condition",
    "verification"
  ]

  alias OfficeGraph.ProjectQuality.DatabaseBoundaryScanner

  @spec compare([map()], [map()], [map()]) :: [map()]
  def compare(current, debt, approved_exceptions) do
    current = Enum.map(current, &normalize_entry/1)
    debt = Enum.map(debt, &normalize_entry/1)
    approved_exceptions = Enum.map(approved_exceptions, &normalize_entry/1)
    recorded = debt ++ approved_exceptions

    inventory_errors(:debt, debt, @debt_metadata_fields) ++
      inventory_errors(
        :approved_exceptions,
        approved_exceptions,
        @approved_metadata_fields
      ) ++
      current_diagnostics(current, recorded) ++
      stale_diagnostics(current, recorded)
  end

  @spec check_repository(Path.t()) :: [map()]
  def check_repository(root \\ File.cwd!()) do
    debt_path =
      Path.join(root, "openspec/specs/ecto-sql-boundaries/database-access-debt.json")

    approved_path =
      Path.join(
        root,
        "openspec/specs/ecto-sql-boundaries/approved-database-exceptions.json"
      )

    compare(
      DatabaseBoundaryScanner.scan_repository(root),
      load_debt_inventory!(debt_path),
      load_approved_inventory!(approved_path)
    )
  end

  @spec decode_debt_inventory!(map()) :: [map()]
  def decode_debt_inventory!(%{
        "version" => 1,
        "status" => "unapproved_removal_debt",
        "occurrence_fields" => fields,
        "files" => files
      })
      when is_list(fields) and is_list(files) do
    Enum.flat_map(files, fn file ->
      path = Map.fetch!(file, "path")
      owner = Map.fetch!(file, "owner")
      remediation_change = Map.fetch!(file, "remediation_change")

      file
      |> Map.fetch!("occurrences")
      |> Enum.map(fn values ->
        if length(values) != length(fields) do
          raise ArgumentError,
                "debt occurrence in #{path} has #{length(values)} values for #{length(fields)} fields"
        end

        fields
        |> Enum.zip(values)
        |> Map.new()
        |> Map.merge(%{
          "owner" => owner,
          "path" => path,
          "remediation_change" => remediation_change
        })
      end)
    end)
  end

  def decode_debt_inventory!(_inventory) do
    raise ArgumentError, "invalid database-access debt inventory schema"
  end

  @spec load_debt_inventory!(Path.t()) :: [map()]
  def load_debt_inventory!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> decode_debt_inventory!()
  end

  @spec load_approved_inventory!(Path.t()) :: [map()]
  def load_approved_inventory!(path) do
    case path |> File.read!() |> Jason.decode!() do
      %{"version" => 1, "exceptions" => exceptions} when is_list(exceptions) -> exceptions
      _inventory -> raise ArgumentError, "invalid approved database exception inventory schema"
    end
  end

  @spec build_debt_inventory([map()]) :: map()
  def build_debt_inventory(occurrences) do
    files =
      occurrences
      |> Enum.group_by(& &1.path)
      |> Enum.map(fn {path, file_occurrences} ->
        %{
          "path" => path,
          "owner" => owner_for_path(path),
          "remediation_change" => remediation_change_for_path(path),
          "occurrences" =>
            Enum.map(file_occurrences, fn occurrence ->
              [
                occurrence.fingerprint,
                to_string(occurrence.class),
                occurrence.construct,
                occurrence.function,
                occurrence.ordinal
              ]
            end)
        }
      end)
      |> Enum.sort_by(& &1["path"])

    %{
      "version" => 1,
      "status" => "unapproved_removal_debt",
      "occurrence_fields" => [
        "fingerprint",
        "class",
        "construct",
        "function",
        "ordinal"
      ],
      "files" => files
    }
  end

  defp current_diagnostics(current, recorded) do
    Enum.flat_map(current, fn occurrence ->
      cond do
        Enum.any?(recorded, &same_fingerprint?(&1, occurrence)) ->
          []

        recorded_occurrence = Enum.find(recorded, &same_locator?(&1, occurrence)) ->
          [
            occurrence
            |> diagnostic(:changed)
            |> Map.put(:recorded_fingerprint, recorded_occurrence["fingerprint"])
          ]

        true ->
          [diagnostic(occurrence, :new)]
      end
    end)
  end

  defp stale_diagnostics(current, recorded) do
    recorded
    |> Enum.reject(fn occurrence ->
      Enum.any?(current, &same_locator?(&1, occurrence))
    end)
    |> Enum.map(&diagnostic(&1, :stale))
  end

  defp inventory_errors(inventory, entries, required_metadata_fields) do
    required_fields =
      ["class", "construct", "fingerprint", "ordinal", "path"] ++
        required_metadata_fields

    entries
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
            inventory: inventory,
            entry: index,
            missing_fields: missing_fields
          }
        ]
      end
    end)
  end

  defp normalize_entry(entry) do
    entry
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.update("class", nil, &to_string/1)
  end

  defp same_fingerprint?(left, right),
    do: left["fingerprint"] == right["fingerprint"]

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

  defp owner_for_path("priv/repo/migrations/" <> _rest), do: "OfficeGraph.Repo.Migrations"
  defp owner_for_path("priv/repo/seeds.exs"), do: "OfficeGraph.Foundation"
  defp owner_for_path("lib/office_graph_web/" <> _rest), do: "OfficeGraphWeb"
  defp owner_for_path("test/office_graph_web/" <> _rest), do: "OfficeGraphWeb"
  defp owner_for_path("test/support/" <> _rest), do: "OfficeGraph.TestSupport"

  defp owner_for_path(path) do
    case String.split(path, "/") do
      [root, "office_graph", area | _rest] when root in ["lib", "test"] ->
        "OfficeGraph.#{area |> Path.rootname() |> Macro.camelize()}"

      _parts ->
        "OfficeGraph.ProjectQuality"
    end
  end

  defp remediation_change_for_path("priv/repo/migrations/" <> _rest),
    do: "rebaseline-unreleased-migrations"

  defp remediation_change_for_path(_path), do: "remove-direct-database-access"
end
