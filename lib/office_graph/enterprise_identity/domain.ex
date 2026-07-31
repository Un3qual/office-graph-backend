defmodule OfficeGraph.EnterpriseIdentity.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.EnterpriseIdentity.EnterpriseConnection
    resource OfficeGraph.EnterpriseIdentity.Directory
    resource OfficeGraph.EnterpriseIdentity.DirectoryUser
    resource OfficeGraph.EnterpriseIdentity.DirectoryGroup
    resource OfficeGraph.EnterpriseIdentity.DirectoryMembership
    resource OfficeGraph.EnterpriseIdentity.DirectorySyncEvent
    resource OfficeGraph.EnterpriseIdentity.ExternalGroupRoleMapping
  end
end
