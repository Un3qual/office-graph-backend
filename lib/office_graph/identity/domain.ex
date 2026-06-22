defmodule OfficeGraph.Identity.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Identity.Principal
    resource OfficeGraph.Identity.PrincipalProfile
    resource OfficeGraph.Identity.Credential
    resource OfficeGraph.Identity.Session
  end
end
