defmodule OfficeGraph.WorkGraph.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.WorkGraph.Signal, :get_signal, :read
      list OfficeGraph.WorkGraph.Signal, :list_signals, :read, relay?: true
    end
  end

  json_api do
    routes do
      base_route "/signals", OfficeGraph.WorkGraph.Signal do
        get(:read, primary?: true)
        index :read
      end
    end
  end

  resources do
    resource OfficeGraph.WorkGraph.RelationshipDefinition
    resource OfficeGraph.WorkGraph.RelationshipEndpointRule
    resource OfficeGraph.WorkGraph.GraphItem
    resource OfficeGraph.WorkGraph.GraphRelationship
    resource OfficeGraph.WorkGraph.Signal
    resource OfficeGraph.WorkGraph.Task
    resource OfficeGraph.WorkGraph.ReviewFinding
    resource OfficeGraph.WorkGraph.VerificationCheck
    resource OfficeGraph.WorkGraph.Artifact
    resource OfficeGraph.WorkGraph.EvidenceCandidate
    resource OfficeGraph.WorkGraph.EvidenceItem
    resource OfficeGraph.WorkGraph.VerificationResult
  end
end
