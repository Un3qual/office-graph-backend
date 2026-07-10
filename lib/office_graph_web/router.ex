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
    get "/packets", OperatorConsoleController, :index
    get "/assets/*path", OperatorConsoleController, :asset
  end

  scope "/api", OfficeGraphWeb do
    pipe_through :api
  end
end
