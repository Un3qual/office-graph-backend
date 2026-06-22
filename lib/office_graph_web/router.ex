defmodule OfficeGraphWeb.Router do
  use OfficeGraphWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  forward "/graphql", Absinthe.Plug, schema: OfficeGraphWeb.Schema

  scope "/api", OfficeGraphWeb do
    pipe_through :api

    post "/manual-intake", WalkingSkeletonController, :manual_intake
    post "/proposed-changes/apply", WalkingSkeletonController, :apply_proposed_changes
    post "/verification/complete", WalkingSkeletonController, :complete_verification
  end
end
