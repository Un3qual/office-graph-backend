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

  scope "/" do
    pipe_through :generated_json_api

    forward "/api/v1", OfficeGraphWeb.JsonApi.Router
  end

  scope "/", OfficeGraphWeb do
    get "/operator", OperatorConsoleController, :index
  end

  scope "/api", OfficeGraphWeb do
    pipe_through :api

    post "/manual-intake", JsonApi.Compatibility.Controller, :manual_intake
    post "/proposed-changes/apply", JsonApi.Compatibility.Controller, :apply_proposed_changes
    post "/verification/complete", JsonApi.Compatibility.Controller, :complete_verification
    post "/packet-run-verification/execute", JsonApi.PacketRunVerification.Controller, :execute
  end
end
