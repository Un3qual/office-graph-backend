defmodule OfficeGraphWeb.Router do
  use OfficeGraphWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser_session do
    plug :fetch_session
    plug :put_secure_browser_headers
    plug OfficeGraphWeb.SameOriginRequestPlug
  end

  pipeline :load_human_session do
    plug OfficeGraphWeb.SessionAuthenticationPlug
  end

  pipeline :require_human_session do
    plug OfficeGraphWeb.RequireHumanSessionPlug
  end

  pipeline :local_development_authentication do
    plug OfficeGraphWeb.Authentication.LocalDevelopmentPlug
    plug :protect_from_forgery
  end

  pipeline :graphql do
    plug :fetch_session
    plug OfficeGraphWeb.SameOriginRequestPlug
    plug OfficeGraphWeb.SessionAuthenticationPlug
    plug AshGraphql.Plug
  end

  pipeline :generated_json_api do
    plug :fetch_session
    plug OfficeGraphWeb.SameOriginRequestPlug
    plug OfficeGraphWeb.SessionAuthenticationPlug
  end

  scope "/" do
    pipe_through :graphql

    forward "/graphql", Absinthe.Plug, schema: Module.concat(["OfficeGraphWeb.GraphQL.Schema"])
  end

  scope "/api", OfficeGraphWeb do
    pipe_through :api

    post "/v1/webhooks/github", GitHubWebhookController, :create
    post "/v1/webhooks/workos", WorkOSWebhookController, :create
  end

  scope "/api", OfficeGraphWeb do
    pipe_through [:api, :generated_json_api]

    get "/v1/graph-items/:item_id/relationships",
        JsonApi.Relationships.Controller,
        :index

    get "/v1/github/installations/:installation_id/health",
        JsonApi.GitHubHealthController,
        :show
  end

  scope "/" do
    pipe_through :generated_json_api

    forward "/api/v1", OfficeGraphWeb.JsonApi.Router
  end

  scope "/", OfficeGraphWeb do
    pipe_through :browser_session

    get "/auth/login", AuthenticationController, :login
    get "/auth/callback", AuthenticationController, :callback
    get "/auth/workos/:connection_id/login", AuthenticationController, :workos_login
    get "/auth/workos/callback", AuthenticationController, :workos_callback
    get "/auth/logged-out", AuthenticationController, :logged_out
    post "/auth/logout", AuthenticationController, :logout
  end

  if Application.compile_env(
       :office_graph,
       :local_development_auth_routes,
       false
     ) do
    scope "/", OfficeGraphWeb.Authentication do
      pipe_through [:browser_session, :local_development_authentication]

      post "/auth/development/login", LocalDevelopmentController, :login
      post "/auth/development/switch", LocalDevelopmentController, :switch
    end
  end

  scope "/", OfficeGraphWeb do
    pipe_through [:browser_session, :load_human_session, :require_human_session]

    get "/operator", OperatorConsoleController, :index
    get "/packets", OperatorConsoleController, :index
    get "/runs", OperatorConsoleController, :index
  end

  scope "/", OfficeGraphWeb do
    get "/assets/*path", OperatorConsoleController, :asset
  end
end
