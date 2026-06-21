defmodule OfficeGraph.WorkGraph.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  resources do
    resource OfficeGraph.WorkGraph.Resources.Signal
    resource OfficeGraph.WorkGraph.Resources.Task
    resource OfficeGraph.WorkGraph.Resources.ReviewFinding
    resource OfficeGraph.WorkGraph.Resources.VerificationCheck
    resource OfficeGraph.WorkGraph.Resources.Artifact
    resource OfficeGraph.WorkGraph.Resources.EvidenceItem
    resource OfficeGraph.WorkGraph.Resources.VerificationResult
  end
end
