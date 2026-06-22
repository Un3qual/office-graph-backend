defmodule OfficeGraph.Revisions.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Revisions.Revision
  end
end
