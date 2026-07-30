defmodule OfficeGraph.Authorization.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Authorization.Capability do
      define :setup_reference_data, action: :setup_catalog
    end

    resource OfficeGraph.Authorization.Role
    resource OfficeGraph.Authorization.RoleCapability
    resource OfficeGraph.Authorization.RoleAssignment
    resource OfficeGraph.Authorization.PolicyBundle
    resource OfficeGraph.Authorization.AuthorizationDecision
  end
end
