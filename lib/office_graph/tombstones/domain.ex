defmodule OfficeGraph.Tombstones.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Tombstones.Tombstone
  end
end
