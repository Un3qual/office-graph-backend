defmodule OfficeGraph.Repo do
  use Boundary, top_level?: true, deps: [], exports: []

  use AshPostgres.Repo,
    otp_app: :office_graph,
    warn_on_missing_ash_functions?: false

  def min_pg_version, do: %Version{major: 17, minor: 0, patch: 0}
end
