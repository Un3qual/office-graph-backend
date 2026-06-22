defmodule OfficeGraph.Integrations.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Integrations.ExternalSource
    resource OfficeGraph.Integrations.RawArchive
    resource OfficeGraph.Integrations.NormalizedIntakeEvent
  end
end
