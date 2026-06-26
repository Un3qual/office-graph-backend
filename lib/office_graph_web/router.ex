defmodule OfficeGraphWeb.Router do
  use OfficeGraphWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  forward "/graphql", Absinthe.Plug, schema: OfficeGraphWeb.Schema

  scope "/", OfficeGraphWeb do
    get "/operator", OperatorConsoleController, :index
  end

  scope "/api", OfficeGraphWeb do
    pipe_through :api

    post "/manual-intake", WalkingSkeletonController, :manual_intake
    post "/proposed-changes/apply", WalkingSkeletonController, :apply_proposed_changes
    post "/verification/complete", WalkingSkeletonController, :complete_verification
    post "/packet-run-verification/execute", PacketRunVerificationController, :execute
    get "/operator-workflow/inbox", OperatorWorkflowController, :inbox
    get "/operator-workflow/items/:id", OperatorWorkflowController, :item
    post "/operator-workflow/packet-readiness", OperatorWorkflowController, :packet_readiness
    get "/operator-workflow/runs/:id", OperatorWorkflowController, :run_state

    get "/operator-workflow/runs/:id/verification-outcome",
        OperatorWorkflowController,
        :verification_outcome
  end
end
