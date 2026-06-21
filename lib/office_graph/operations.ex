defmodule OfficeGraph.Operations do
  @moduledoc """
  Public boundary for operation correlation and mutation context.
  """

  use Boundary, deps: [OfficeGraph], exports: []

  alias OfficeGraph.Operations.OperationCorrelation

  @actions %{
    manual_intake_submit: "manual_intake.submit",
    proposed_change_apply: "proposed_change.apply",
    evidence_link: "evidence.link",
    verification_complete: "verification.complete",
    skeleton_read: "skeleton.read"
  }

  def start_operation(session_context, action, attrs \\ []) do
    action_name = Map.fetch!(@actions, action)
    correlation_id = Keyword.get_lazy(attrs, :correlation_id, &Ecto.UUID.generate/0)

    OperationCorrelation
    |> Ash.Changeset.for_create(:create, %{
      id: Ecto.UUID.generate(),
      principal_id: session_context.principal_id,
      session_id: session_context.session_id,
      organization_id: session_context.organization_id,
      workspace_id: session_context.workspace_id,
      action: action_name,
      correlation_id: correlation_id,
      idempotency_key: attrs[:idempotency_key],
      metadata: Map.new(attrs[:metadata] || %{})
    })
    |> Ash.create(authorize?: false)
  end
end
