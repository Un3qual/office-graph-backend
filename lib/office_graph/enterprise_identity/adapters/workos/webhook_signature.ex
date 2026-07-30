defmodule OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.WebhookSignature do
  @moduledoc false

  @default_tolerance_seconds 180
  @maximum_header_bytes 2_048
  @signature_pattern ~r/\A[0-9a-fA-F]{64}\z/

  def verify(raw_body, header, secret, opts \\ [])

  def verify(raw_body, header, secret, opts)
      when is_binary(raw_body) and is_binary(header) and is_binary(secret) and
             byte_size(header) <= @maximum_header_bytes and is_list(opts) do
    now_unix = Keyword.get(opts, :now_unix, System.system_time(:second))
    tolerance_seconds = Keyword.get(opts, :tolerance_seconds, @default_tolerance_seconds)

    with true <- is_integer(now_unix),
         true <- is_integer(tolerance_seconds) and tolerance_seconds >= 0,
         {:ok, timestamp, signatures} <- parse_header(header),
         true <- abs(now_unix - timestamp) <= tolerance_seconds,
         expected <- expected_signature(raw_body, timestamp, secret),
         true <- Enum.any?(signatures, &secure_match?(&1, expected)) do
      :ok
    else
      _invalid -> {:error, :invalid_signature}
    end
  end

  def verify(_raw_body, _header, _secret, _opts), do: {:error, :invalid_signature}

  defp parse_header(header) do
    fields =
      header
      |> String.split(",", trim: true)
      |> Enum.map(&String.split(String.trim(&1), "=", parts: 2))

    timestamp =
      Enum.find_value(fields, fn
        ["t", value] ->
          case Integer.parse(value) do
            {parsed, ""} when parsed >= 0 -> parsed
            _invalid -> nil
          end

        _other ->
          nil
      end)

    signatures =
      Enum.flat_map(fields, fn
        ["v1", value] ->
          if Regex.match?(@signature_pattern, value), do: [String.downcase(value)], else: []

        _other ->
          []
      end)

    if is_integer(timestamp) and signatures != [],
      do: {:ok, timestamp, signatures},
      else: {:error, :invalid_signature}
  end

  defp expected_signature(raw_body, timestamp, secret) do
    :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{raw_body}")
    |> Base.encode16(case: :lower)
  end

  defp secure_match?(supplied, expected) when byte_size(supplied) == byte_size(expected),
    do: :crypto.hash_equals(supplied, expected)

  defp secure_match?(_supplied, _expected), do: false
end
