defmodule OfficeGraph.GitHubIntegration.WebhookSignature do
  @moduledoc false

  def verify(raw_body, "sha256=" <> supplied_hex, secret)
      when is_binary(raw_body) and is_binary(secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, raw_body)

    with {:ok, supplied} <- Base.decode16(supplied_hex, case: :mixed),
         true <- byte_size(supplied) == byte_size(expected),
         true <- :crypto.hash_equals(supplied, expected) do
      :ok
    else
      _reason -> {:error, :invalid_signature}
    end
  end

  def verify(_raw_body, _signature, _secret), do: {:error, :invalid_signature}
end
