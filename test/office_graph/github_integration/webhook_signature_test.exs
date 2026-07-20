defmodule OfficeGraph.GitHubIntegration.WebhookSignatureTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.GitHubIntegration.WebhookSignature

  test "verifies sha256 HMAC signatures without accepting malformed encodings" do
    body = ~s({"installation":{"id":42}})
    secret = "webhook-signing-secret"
    signature = "sha256=" <> (:crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16())

    assert :ok = WebhookSignature.verify(body, signature, secret)
    assert {:error, :invalid_signature} = WebhookSignature.verify(body <> " ", signature, secret)
    assert {:error, :invalid_signature} = WebhookSignature.verify(body, "sha256=not-hex", secret)
    assert {:error, :invalid_signature} = WebhookSignature.verify(body, "sha1=legacy", secret)
  end
end
