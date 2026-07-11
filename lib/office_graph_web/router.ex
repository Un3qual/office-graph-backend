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

    post "/v1/commands/submit-manual-intake",
         JsonApi.OperatorCommands.IntakeController,
         :submit_manual_intake

    post "/v1/commands/apply-proposed-changes",
         JsonApi.OperatorCommands.IntakeController,
         :apply_proposed_changes
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
