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
  end

  scope "/api", OfficeGraphWeb do
    pipe_through [:api, :generated_json_api]

    get "/v1/graph-items/:item_id/relationships",
        JsonApi.Relationships.Controller,
        :index

    post "/v1/commands/bind-github-installation",
         JsonApi.OperatorCommands.GitHubController,
         :bind_installation

    post "/v1/commands/reply-to-github-review",
         JsonApi.OperatorCommands.GitHubController,
         :reply_to_review

    post "/v1/commands/update-github-check",
         JsonApi.OperatorCommands.GitHubController,
         :update_check

    get "/v1/github/installations/:installation_id/health",
        JsonApi.GitHubHealthController,
        :show

    post "/v1/commands/resolve-agent-approval",
         JsonApi.OperatorCommands.AgentsController,
         :resolve_approval

    post "/v1/commands/resolve-agent-context-expansion",
         JsonApi.OperatorCommands.AgentsController,
         :resolve_context_expansion

    post "/v1/commands/invoke-agent",
         JsonApi.OperatorCommands.AgentsController,
         :invoke_agent

    post "/v1/commands/cancel-agent-execution",
         JsonApi.OperatorCommands.AgentsController,
         :cancel_agent_execution

    post "/v1/commands/start-run-conversation",
         JsonApi.OperatorCommands.AgentsController,
         :start_conversation

    post "/v1/commands/append-conversation-message",
         JsonApi.OperatorCommands.AgentsController,
         :append_conversation_message
  end

  scope "/" do
    pipe_through :generated_json_api

    forward "/api/v1", OfficeGraphWeb.JsonApi.Router
  end

  scope "/", OfficeGraphWeb do
    pipe_through :browser_session

    get "/auth/login", AuthenticationController, :login
    get "/auth/callback", AuthenticationController, :callback
    get "/auth/logged-out", AuthenticationController, :logged_out
    post "/auth/logout", AuthenticationController, :logout
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
