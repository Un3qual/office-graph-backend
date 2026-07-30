defmodule OfficeGraph.EnterpriseIdentity.EnterpriseSsoClient do
  @moduledoc """
  Provider adapter contract for enterprise browser SSO authorization and profile exchange.
  """

  @callback authorization_uri(request :: map()) ::
              {:ok, String.t()} | {:error, term()}

  @callback exchange(request :: map()) ::
              {:ok, map()} | {:error, term()}
end
