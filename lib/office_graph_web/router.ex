defmodule OfficeGraphWeb.Router do
  use OfficeGraphWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  forward "/graphql", Absinthe.Plug, schema: OfficeGraphWeb.GraphQL.Schema

  scope "/", OfficeGraphWeb do
    get "/operator", OperatorConsoleController, :index
  end

  scope "/api", OfficeGraphWeb do
    pipe_through :api

    post "/manual-intake", JsonApi.Compatibility.Controller, :manual_intake
    post "/proposed-changes/apply", JsonApi.Compatibility.Controller, :apply_proposed_changes
    post "/verification/complete", JsonApi.Compatibility.Controller, :complete_verification
    post "/packet-run-verification/execute", JsonApi.PacketRunVerification.Controller, :execute
    get "/operator-workflow/inbox", JsonApi.OperatorWorkflow.Controller, :inbox
    get "/operator-workflow/items/:id", JsonApi.OperatorWorkflow.Controller, :item

    post "/operator-workflow/packet-readiness",
         JsonApi.OperatorWorkflow.Controller,
         :packet_readiness

    get "/operator-workflow/runs/:id", JsonApi.OperatorWorkflow.Controller, :run_state

    get "/operator-workflow/runs/:id/verification-outcome",
        JsonApi.OperatorWorkflow.Controller,
        :verification_outcome
  end
end
