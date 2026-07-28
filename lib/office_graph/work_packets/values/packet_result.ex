defmodule OfficeGraph.WorkPackets.PacketResult do
  @moduledoc """
  Passive result DTO for an atomically assembled packet, version, and child rows.
  """

  @enforce_keys [:packet, :version, :source_references, :required_checks]
  defstruct @enforce_keys
end
