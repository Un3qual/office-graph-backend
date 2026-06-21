defmodule OfficeGraph.Tenancy.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Tenancy.Organization
    resource OfficeGraph.Tenancy.Workspace
    resource OfficeGraph.Tenancy.Initiative
    resource OfficeGraph.Tenancy.Workstream
  end
end
