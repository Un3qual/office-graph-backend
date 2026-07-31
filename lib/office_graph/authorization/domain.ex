defmodule OfficeGraph.Authorization.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Authorization.Capability do
      define :setup_reference_data, action: :setup_catalog
    end

    resource OfficeGraph.Authorization.Role do
      define :local_development_login_roles,
        action: :read_for_local_development_login,
        args: [:role_ids]
    end

    resource OfficeGraph.Authorization.RoleCapability do
      define :local_development_login_role_capabilities,
        action: :read_for_local_development_login,
        args: [:role_ids]
    end

    resource OfficeGraph.Authorization.RoleAssignment do
      define :local_development_login_assignments,
        action: :read_for_local_development_login,
        args: [:principal_id]
    end

    resource OfficeGraph.Authorization.PolicyBundle
    resource OfficeGraph.Authorization.AuthorizationDecision
  end
end
