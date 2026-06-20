defmodule OfficeGraph.Repo do
  use Ecto.Repo,
    otp_app: :office_graph,
    adapter: Ecto.Adapters.Postgres
end
