defmodule OfficeGraph.Audit.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Audit.AuditRecord
  end
end
