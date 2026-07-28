defmodule OfficeGraph.WorkGraph.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.WorkGraph.GraphItem, :get_graph_item, :read
      list OfficeGraph.WorkGraph.GraphItem, :list_graph_items, :read, relay?: true

      get OfficeGraph.WorkGraph.Signal, :get_signal, :read
      list OfficeGraph.WorkGraph.Signal, :list_signals, :read, relay?: true

      get OfficeGraph.WorkGraph.Task, :get_task, :read
      list OfficeGraph.WorkGraph.Task, :list_tasks, :read, relay?: true

      get OfficeGraph.WorkGraph.ReviewFinding, :get_review_finding, :read
      list OfficeGraph.WorkGraph.ReviewFinding, :list_review_findings, :read, relay?: true

      get OfficeGraph.WorkGraph.VerificationCheck, :get_verification_check, :read
      list OfficeGraph.WorkGraph.VerificationCheck, :list_verification_checks, :read, relay?: true

      get OfficeGraph.WorkGraph.EvidenceCandidate, :get_evidence_candidate, :read
      list OfficeGraph.WorkGraph.EvidenceCandidate, :list_evidence_candidates, :read, relay?: true

      get OfficeGraph.WorkGraph.EvidenceItem, :get_evidence_item, :read
      list OfficeGraph.WorkGraph.EvidenceItem, :list_evidence_items, :read, relay?: true

      get OfficeGraph.WorkGraph.Artifact, :get_artifact, :read
      list OfficeGraph.WorkGraph.Artifact, :list_artifacts, :read, relay?: true

      get OfficeGraph.WorkGraph.VerificationResult, :get_verification_result, :read

      list OfficeGraph.WorkGraph.VerificationResult, :list_verification_results, :read,
        relay?: true
    end

    mutations do
      action OfficeGraph.WorkGraph.EvidenceCandidate,
             :create_evidence_candidate,
             :create_evidence_candidate do
        relay_id_translations(
          input: [
            work_run_id: :work_run,
            verification_check_id: :verification_check,
            execution_observation_id: :execution_observation
          ]
        )
      end

      action OfficeGraph.WorkGraph.EvidenceCandidate, :accept_evidence, :accept_evidence do
        relay_id_translations(input: [evidence_candidate_id: :evidence_candidate])
      end
    end
  end

  json_api do
    routes do
      base_route "/graph-items", OfficeGraph.WorkGraph.GraphItem do
        get(:read, primary?: true)
        index :read
        related(:signal, :read)
        related(:task, :read)
        related(:review_finding, :read)
        related(:verification_check, :read)
        related(:artifact, :read)
      end

      base_route "/signals", OfficeGraph.WorkGraph.Signal do
        get(:read, primary?: true)
        index :read
        related(:graph_item, :read)
        related(:tasks, :read)
      end

      base_route "/tasks", OfficeGraph.WorkGraph.Task do
        get(:read, primary?: true)
        index :read
        related(:graph_item, :read)
        related(:source_signal, :read)
        related(:review_findings, :read)
      end

      base_route "/review-findings", OfficeGraph.WorkGraph.ReviewFinding do
        get(:read, primary?: true)
        index :read
        related(:graph_item, :read)
        related(:task, :read)
        related(:verification_checks, :read)
      end

      base_route "/verification-checks", OfficeGraph.WorkGraph.VerificationCheck do
        get(:read, primary?: true)
        index :read
        related(:graph_item, :read)
        related(:review_finding, :read)
        related(:evidence_candidates, :read)
        related(:evidence_items, :read)
        related(:verification_results, :read)
      end

      base_route "/evidence-candidates", OfficeGraph.WorkGraph.EvidenceCandidate do
        get(:read, primary?: true)
        index :read
      end

      base_route "/evidence-items", OfficeGraph.WorkGraph.EvidenceItem do
        get(:read, primary?: true)
        index :read
      end

      base_route "/artifacts", OfficeGraph.WorkGraph.Artifact do
        get(:read, primary?: true)
        index :read
        related(:graph_item, :read)
        related(:evidence_candidates, :read)
        related(:evidence_items, :read)
      end

      base_route "/verification-results", OfficeGraph.WorkGraph.VerificationResult do
        get(:read, primary?: true)
        index :read
      end

      route(
        OfficeGraph.WorkGraph.EvidenceCandidate,
        :post,
        "/commands/create-evidence-candidate",
        :create_evidence_candidate
      )

      route(
        OfficeGraph.WorkGraph.EvidenceCandidate,
        :post,
        "/commands/accept-evidence",
        :accept_evidence
      )
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
