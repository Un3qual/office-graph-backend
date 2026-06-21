defmodule OfficeGraph.ExternalRefs.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.ExternalRefs.ExternalReference
  end
end
