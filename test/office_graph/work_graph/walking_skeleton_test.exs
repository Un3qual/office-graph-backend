defmodule OfficeGraph.WorkGraph.WalkingSkeletonTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.{Audit, Revisions}
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph.Resources.{
    ReviewFinding,
    Signal,
    Task,
    VerificationCheck
  }

  test "manual intake progresses through proposed changes to verified completion" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, intake_operation} = Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert {:ok, intake} =
             Integrations.submit_manual_intake(bootstrap.session, intake_operation, %{
               source_identity: "manual:web",
               replay_identity: "paste:walkthrough-1",
               body: "Investigate flaky deploy and prove it with a passing deployment check."
             })

    assert intake.normalized_event.outcome == "accepted"

    assert Enum.map(intake.proposed_changes, & &1.change_type) == [
             "create_signal",
             "create_task",
             "create_review_finding",
             "create_verification_check"
           ]

    {:ok, apply_operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    assert {:ok, applied} =
             ProposedChanges.apply_all(
               bootstrap.session,
               apply_operation,
               intake.proposed_changes
             )

    assert applied.signal.state == "open"
    assert applied.task.lifecycle_state == "open"
    assert applied.review_finding.lifecycle_state == "open"
    assert applied.verification_check.lifecycle_state == "required"
    assert %Signal{} = applied.signal
    assert %Task{} = applied.task
    assert %ReviewFinding{} = applied.review_finding
    assert %VerificationCheck{} = applied.verification_check

    {:ok, evidence_operation} = Operations.start_operation(bootstrap.session, :evidence_link)

    assert {:ok, completed} =
             Verification.complete_with_evidence(
               bootstrap.session,
               evidence_operation,
               applied.verification_check,
               %{
                 title: "Deploy check passed",
                 body: "Deployment check passed on the verification run.",
                 artifact_uri: "https://example.test/deploy/123"
               }
             )

    assert completed.evidence_item.state == "accepted"
    assert completed.verification_result.result == "passed"
    assert completed.verification_check.lifecycle_state == "satisfied"
    assert completed.review_finding.lifecycle_state == "verified_complete"
    assert completed.task.lifecycle_state == "verified_complete"

    assert Audit.count_for_operation(apply_operation.id) >= 4
    assert Revisions.count_for_operation(apply_operation.id) >= 4
    assert Audit.count_for_operation(evidence_operation.id) >= 4
    assert Revisions.count_for_operation(evidence_operation.id) >= 4
  end
end
