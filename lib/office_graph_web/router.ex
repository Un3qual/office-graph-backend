defmodule OfficeGraphWeb.Router do
  use OfficeGraphWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :graphql do
    plug OfficeGraphWeb.LocalApiOwnerPlug
    plug AshGraphql.Plug
  end

  pipeline :generated_json_api do
    plug OfficeGraphWeb.LocalApiOwnerPlug
  end

  scope "/" do
    pipe_through :graphql

    forward "/graphql", Absinthe.Plug, schema: Module.concat(["OfficeGraphWeb.GraphQL.Schema"])
  end

  scope "/api", OfficeGraphWeb do
    pipe_through [:api, :generated_json_api]

    get "/v1/graph-items/:item_id/relationships",
        JsonApi.Relationships.Controller,
        :index

    post "/v1/commands/submit-manual-intake",
         JsonApi.OperatorCommands.IntakeController,
         :submit_manual_intake

    post "/v1/commands/bind-github-installation",
         JsonApi.OperatorCommands.GitHubController,
         :bind_installation

    post "/v1/commands/apply-proposed-changes",
         JsonApi.OperatorCommands.IntakeController,
         :apply_proposed_changes

    post "/v1/commands/create-work-packet",
         JsonApi.OperatorCommands.PacketsController,
         :create_work_packet

    post "/v1/commands/create-work-packet-version",
         JsonApi.OperatorCommands.PacketsController,
         :create_work_packet_version

    post "/v1/commands/start-work-run",
         JsonApi.OperatorCommands.RunsController,
         :start_work_run

    post "/v1/commands/record-execution-observation",
         JsonApi.OperatorCommands.RunsController,
         :record_execution_observation

    post "/v1/commands/create-evidence-candidate",
         JsonApi.OperatorCommands.VerificationController,
         :create_evidence_candidate

    post "/v1/commands/accept-evidence",
         JsonApi.OperatorCommands.VerificationController,
         :accept_evidence

    post "/v1/commands/waive-verification-check",
         JsonApi.OperatorCommands.VerificationController,
         :waive_verification_check
  end

  scope "/" do
    pipe_through :generated_json_api

    forward "/api/v1", OfficeGraphWeb.JsonApi.Router
  end

  scope "/", OfficeGraphWeb do
    get "/operator", OperatorConsoleController, :index
    get "/packets", OperatorConsoleController, :index
    get "/assets/*path", OperatorConsoleController, :asset
  end
end
