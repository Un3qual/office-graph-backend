defmodule OfficeGraphWeb.WalkingSkeletonSerializer do
  @moduledoc false

  def intake(intake) do
    %{
      normalized_event: %{
        id: intake.normalized_event.id,
        outcome: intake.normalized_event.outcome
      },
      proposed_changes: Enum.map(intake.proposed_changes, &proposed_change/1)
    }
  end

  def applied(applied) do
    %{
      signal: lifecycle(applied.signal),
      task: lifecycle(applied.task),
      review_finding: lifecycle(applied.review_finding),
      verification_check: lifecycle(applied.verification_check)
    }
  end

  def completed(completed) do
    %{
      evidence_item: lifecycle(completed.evidence_item),
      verification_result: %{
        id: completed.verification_result.id,
        result: completed.verification_result.result
      },
      task: lifecycle(completed.task),
      review_finding: lifecycle(completed.review_finding),
      verification_check: lifecycle(completed.verification_check)
    }
  end

  defp proposed_change(change) do
    %{
      id: change.id,
      change_type: change.change_type,
      status: change.status
    }
  end

  defp lifecycle(resource) do
    %{
      id: resource.id,
      state: Map.get(resource, :state),
      lifecycle_state: Map.get(resource, :lifecycle_state)
    }
  end
end
