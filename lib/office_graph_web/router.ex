defmodule OfficeGraphWeb.Router do
  use OfficeGraphWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", OfficeGraphWeb do
    pipe_through :api
  end
end
