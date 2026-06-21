defmodule OfficeGraph.Foundation.Bootstrap do
  @moduledoc """
  Result returned by the local/test owner bootstrap path.
  """

  defstruct [
    :organization,
    :workspace,
    :initiative,
    :principal,
    :profile,
    :session,
    :role_assignment,
    :policy_bundle
  ]
end
