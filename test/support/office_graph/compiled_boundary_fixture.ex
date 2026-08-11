defmodule OfficeGraph.TestSupport.CompiledBoundaryFixture do
  @moduledoc false

  def approved_source_path!(source_path, approved_sources) do
    fingerprint =
      source_path
      |> File.read!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    if fingerprint in Map.values(approved_sources) do
      source_path
    else
      raise ArgumentError,
            "generated compiler fixture source is not approved: sha256:#{fingerprint}"
    end
  end
end
