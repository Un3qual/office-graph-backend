defmodule OfficeGraph.WorkGraph.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.WorkGraph.Signal, :get_signal, :read
      list OfficeGraph.WorkGraph.Signal, :list_signals, :read, relay?: true

      get OfficeGraph.WorkGraph.EvidenceCandidate, :get_evidence_candidate, :read
      list OfficeGraph.WorkGraph.EvidenceCandidate, :list_evidence_candidates, :read, relay?: true

      get OfficeGraph.WorkGraph.EvidenceItem, :get_evidence_item, :read
      list OfficeGraph.WorkGraph.EvidenceItem, :list_evidence_items, :read, relay?: true

      get OfficeGraph.WorkGraph.VerificationResult, :get_verification_result, :read

      list OfficeGraph.WorkGraph.VerificationResult, :list_verification_results, :read,
        relay?: true
    end
  end

  json_api do
    routes do
      base_route "/signals", OfficeGraph.WorkGraph.Signal do
        get(:read, primary?: true)
        index :read
      end

      base_route "/evidence-candidates", OfficeGraph.WorkGraph.EvidenceCandidate do
        get(:read, primary?: true)
        index :read
      end

      base_route "/evidence-items", OfficeGraph.WorkGraph.EvidenceItem do
        get(:read, primary?: true)
        index :read
      end

      base_route "/verification-results", OfficeGraph.WorkGraph.VerificationResult do
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
