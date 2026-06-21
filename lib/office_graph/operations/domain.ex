defmodule OfficeGraph.Operations.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Operations.OperationCorrelation
  end
end
