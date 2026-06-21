defmodule OfficeGraph.WorkGraph.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  resources do
    resource OfficeGraph.WorkGraph.GraphItem
    resource OfficeGraph.WorkGraph.GraphRelationship
    resource OfficeGraph.WorkGraph.Signal
    resource OfficeGraph.WorkGraph.Task
    resource OfficeGraph.WorkGraph.ReviewFinding
    resource OfficeGraph.WorkGraph.VerificationCheck
    resource OfficeGraph.WorkGraph.Artifact
    resource OfficeGraph.WorkGraph.EvidenceItem
    resource OfficeGraph.WorkGraph.VerificationResult
  end
end
