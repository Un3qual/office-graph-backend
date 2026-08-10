defmodule OfficeGraph.ProjectQuality.DatabaseBoundaryGate do
  @moduledoc """
  Requires every detected database-access occurrence to match an explicitly
  approved exception.
  """

  @locator_fields ["path", "line", "class", "construct", "function", "ordinal"]
  @approved_metadata_fields [
    "approving_change",
    "owner",
    "reason",
    "retirement_condition",
    "verification"
  ]
  @terminal_object_classes [
    "extension",
    "grant",
    "materialized view",
    "materialized view index",
    "RLS policy",
    "RLS state",
    "routine",
    "trigger",
    "view"
  ]
  @required_string_fields ["class", "construct", "fingerprint", "path"] ++
                            @approved_metadata_fields
  @approval_evidence_fields @locator_fields ++
                              ["fingerprint", "terminal_objects"] ++ @approved_metadata_fields
  @approval_evidence_file "database-exception-approvals.json"

  alias OfficeGraph.ProjectQuality.DatabaseBoundaryScanner

  @spec compare([map()], [map()]) :: [map()]
  def compare(current, approved_exceptions) do
    current = Enum.map(current, &normalize_entry/1)

    approved_exceptions =
      Enum.map(approved_exceptions, &normalize_entry(&1, :approved_exceptions))

    compare_normalized(current, approved_exceptions)
  end

  defp compare_normalized(current, approved_exceptions) do
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

    current = DatabaseBoundaryScanner.scan_repository(root) |> Enum.map(&normalize_entry/1)
    compiled = DatabaseBoundaryScanner.scan_compiled(root) |> Enum.map(&normalize_entry/1)

    approved_exceptions =
      approved_path
      |> load_approved_inventory!()
      |> Enum.map(&normalize_entry(&1, :approved_exceptions))

    case inventory_errors(approved_exceptions) do
      [] ->
        case approval_provenance_errors(root, approved_exceptions) do
          [] ->
            compare_normalized(current, approved_exceptions) ++
              compiled_diagnostics(compiled, current)

          errors ->
            errors
        end

      errors ->
        errors
    end
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
        :unresolved ->
          [diagnostic(occurrence, :unresolved)]

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
    if occurrence["approval"] == :unresolved_sql do
      :unresolved
    else
      Enum.reduce_while(approved_exceptions, :new, fn approved_exception, match ->
        cond do
          same_locator?(approved_exception, occurrence) and
              approved_exception["fingerprint"] == occurrence["fingerprint"] ->
            {:halt, :exact}

          same_locator?(approved_exception, occurrence) ->
            {:cont, {:changed, approved_exception}}

          true ->
            {:cont, match}
        end
      end)
    end
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

  defp compiled_diagnostics(compiled, current) do
    source_counts =
      current
      |> Enum.reject(&(Map.get(&1, "compiled_match?", true) == false))
      |> Enum.frequencies_by(&compiled_source_key/1)

    compiled
    |> Enum.map_reduce(source_counts, fn occurrence, remaining ->
      key = compiled_source_key(occurrence)

      case Map.get(remaining, key, 0) do
        count when count > 0 ->
          {nil, Map.put(remaining, key, count - 1)}

        _count ->
          {diagnostic(occurrence, :compiled_reference), remaining}
      end
    end)
    |> elem(0)
    |> Enum.reject(&is_nil/1)
  end

  defp compiled_source_key(entry) do
    {
      Map.get(entry, "path"),
      Map.get(entry, "line"),
      Map.get(entry, "class"),
      Map.get(entry, "construct"),
      Map.get(entry, "function")
    }
  end

  defp inventory_errors(approved_exceptions) do
    required_fields =
      ["class", "construct", "fingerprint", "line", "ordinal", "path"] ++
        @approved_metadata_fields

    missing_field_errors =
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

    invalid_field_errors =
      approved_exceptions
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {entry, index} ->
        case invalid_fields(entry) do
          [] ->
            []

          fields ->
            [
              %{
                kind: :invalid_inventory,
                inventory: :approved_exceptions,
                entry: index,
                invalid_fields: fields
              }
            ]
        end
      end)

    missing_field_errors ++
      invalid_field_errors ++
      duplicate_locator_errors(approved_exceptions)
  end

  defp approval_provenance_errors(root, approved_exceptions) do
    approved_exceptions
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {entry, index} ->
      change = entry["approving_change"]

      root
      |> approval_change_directories(change)
      |> approval_provenance_error(entry, index, change)
    end)
  end

  defp approval_change_directories(root, change) do
    active_change = Path.join(root, "openspec/changes/#{change}")

    archived_change_pattern =
      ~r/^\d{4}-\d{2}-\d{2}-#{Regex.escape(change)}$/

    archived_changes =
      root
      |> Path.join("openspec/changes/archive/*")
      |> Path.wildcard()
      |> Enum.filter(fn path ->
        File.dir?(path) and Regex.match?(archived_change_pattern, Path.basename(path))
      end)

    [active_change | archived_changes]
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
  end

  defp approval_provenance_error([], entry, index, change) do
    [approval_provenance_diagnostic(entry, index, change, :missing_change)]
  end

  defp approval_provenance_error([change_root], entry, index, change) do
    evidence_path = Path.join(change_root, @approval_evidence_file)

    case load_approval_evidence(evidence_path) do
      {:ok, approvals} ->
        if Enum.any?(approvals, &same_approval_evidence?(&1, entry)) do
          []
        else
          [approval_provenance_diagnostic(entry, index, change, :unrecorded_exception)]
        end

      {:error, reason} ->
        [approval_provenance_diagnostic(entry, index, change, reason)]
    end
  end

  defp approval_provenance_error(change_roots, entry, index, change) do
    [
      entry
      |> approval_provenance_diagnostic(index, change, :ambiguous_change)
      |> Map.put(:change_paths, change_roots)
    ]
  end

  defp load_approval_evidence(path) do
    with {:ok, body} <- File.read(path),
         {:ok, %{"version" => 1, "approvals" => approvals}} when is_list(approvals) <-
           Jason.decode(body) do
      {:ok, approvals}
    else
      {:error, :enoent} -> {:error, :missing_approval_evidence}
      {:error, _reason} -> {:error, :invalid_approval_evidence}
      _invalid_schema -> {:error, :invalid_approval_evidence}
    end
  end

  defp same_approval_evidence?(evidence, entry) when is_map(evidence) do
    Enum.all?(@approval_evidence_fields, &(Map.get(evidence, &1) == Map.get(entry, &1)))
  end

  defp same_approval_evidence?(_evidence, _entry), do: false

  defp approval_provenance_diagnostic(entry, index, change, reason) do
    %{
      kind: :invalid_approval_provenance,
      inventory: :approved_exceptions,
      entry: index,
      approving_change: change,
      fingerprint: entry["fingerprint"],
      reason: reason
    }
  end

  defp duplicate_locator_errors(approved_exceptions) do
    approved_exceptions
    |> Enum.with_index(1)
    |> Enum.filter(fn {entry, _index} -> valid_locator?(entry) end)
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
          line: entry["line"],
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
    |> Map.update("class", nil, &normalize_class/1)
  end

  defp normalize_entry(entry, inventory) when is_map(entry) do
    entry
    |> normalize_entry()
    |> Map.put("inventory", inventory)
  end

  defp normalize_entry(_entry, inventory), do: %{"inventory" => inventory}

  defp same_locator?(left, right) do
    Enum.all?(@locator_fields, &(Map.get(left, &1) == Map.get(right, &1)))
  end

  defp invalid_fields(entry) do
    invalid_strings =
      Enum.filter(@required_string_fields, fn field ->
        value = Map.get(entry, field)
        not blank?(value) and not is_binary(value)
      end)

    invalid_function =
      case Map.get(entry, "function") do
        nil -> []
        value when is_binary(value) and value != "" -> []
        _value -> ["function"]
      end

    invalid_ordinal =
      entry
      |> Map.get("ordinal")
      |> case do
        value when is_integer(value) and value > 0 -> []
        value -> if blank?(value), do: [], else: ["ordinal"]
      end

    invalid_line =
      entry
      |> Map.get("line")
      |> case do
        value when is_integer(value) and value > 0 -> []
        value -> if blank?(value), do: [], else: ["line"]
      end

    invalid_approving_change =
      case Map.get(entry, "approving_change") do
        value when is_binary(value) and value != "" ->
          if Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, value),
            do: [],
            else: ["approving_change"]

        _value ->
          []
      end

    invalid_terminal_objects =
      case Map.get(entry, "terminal_objects") do
        nil ->
          []

        terminal_objects when is_list(terminal_objects) ->
          if Enum.all?(terminal_objects, &valid_terminal_object?/1),
            do: [],
            else: ["terminal_objects"]

        _terminal_objects ->
          ["terminal_objects"]
      end

    (invalid_strings ++
       invalid_function ++
       invalid_line ++
       invalid_ordinal ++ invalid_approving_change ++ invalid_terminal_objects)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp valid_terminal_object?(%{
         "class" => class,
         "identity" => identity,
         "fingerprint" => "sha256:" <> hash
       }) do
    class in @terminal_object_classes and is_binary(identity) and identity != "" and
      Regex.match?(~r/\A[0-9a-f]{64}\z/, hash)
  end

  defp valid_terminal_object?(_terminal_object), do: false

  defp valid_locator?(entry) do
    is_binary(entry["path"]) and entry["path"] != "" and
      is_binary(entry["class"]) and entry["class"] != "" and
      is_binary(entry["construct"]) and entry["construct"] != "" and
      (is_nil(entry["function"]) or
         (is_binary(entry["function"]) and entry["function"] != "")) and
      is_integer(entry["line"]) and entry["line"] > 0 and
      is_integer(entry["ordinal"]) and entry["ordinal"] > 0
  end

  defp normalize_class(nil), do: nil
  defp normalize_class(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_class(value), do: value

  defp diagnostic(occurrence, kind) do
    diagnostic = %{
      kind: kind,
      class: occurrence["class"],
      construct: occurrence["construct"],
      fingerprint: occurrence["fingerprint"],
      function: occurrence["function"],
      line: occurrence["line"],
      ordinal: occurrence["ordinal"],
      path: occurrence["path"]
    }

    case Map.fetch(occurrence, "approval") do
      {:ok, approval} -> Map.put(diagnostic, :approval, approval)
      :error -> diagnostic
    end
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
