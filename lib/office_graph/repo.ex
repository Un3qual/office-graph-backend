defmodule OfficeGraph.Repo do
  use Boundary, top_level?: true, deps: [], exports: []

  use Ecto.Repo,
    otp_app: :office_graph,
    adapter: Ecto.Adapters.Postgres
end
