defmodule OfficeGraph.WorkPackets.PacketResult do
  @moduledoc false

  @enforce_keys [:packet, :version, :source_references, :required_checks]
  defstruct @enforce_keys
end
