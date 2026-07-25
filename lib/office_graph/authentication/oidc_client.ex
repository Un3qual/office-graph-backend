defmodule OfficeGraph.Authentication.OidcClient do
  @moduledoc """
  Protocol boundary for the human OpenID Connect authorization-code flow.
  """

  @callback authorization_uri(request :: map()) ::
              {:ok, String.t()} | {:error, term()}

  @callback exchange(request :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback logout_uri(request :: map()) ::
              {:ok, String.t()} | {:error, term()}
end
