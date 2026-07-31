defmodule OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.HTTPClient do
  @moduledoc false

  @callback request(
              method :: :get | :post,
              url :: String.t(),
              headers :: %{String.t() => String.t()},
              body :: String.t() | nil
            ) ::
              {:ok, %{status: pos_integer(), headers: map(), body: binary()}}
              | {:error, term()}
end

defmodule OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.HTTPClient.Httpc do
  @moduledoc false

  @behaviour OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.HTTPClient

  @connect_timeout 5_000
  @request_timeout 15_000
  @maximum_response_bytes 1_000_000

  @impl true
  def request(method, url, headers, body) when method in [:get, :post] do
    request_headers =
      Enum.map(headers, fn {name, value} ->
        {String.to_charlist(name), String.to_charlist(value)}
      end)

    request =
      case method do
        :get ->
          {String.to_charlist(url), request_headers}

        :post ->
          content_type = Map.get(headers, "content-type", "application/json")

          {
            String.to_charlist(url),
            request_headers,
            String.to_charlist(content_type),
            body || ""
          }
      end

    case :httpc.request(
           method,
           request,
           [
             connect_timeout: @connect_timeout,
             timeout: @request_timeout,
             ssl: [
               verify: :verify_peer,
               cacerts: :public_key.cacerts_get(),
               customize_hostname_check: [
                 match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
               ]
             ]
           ],
           sync: false,
           stream: {:self, :once},
           receiver: self()
         ) do
      {:ok, request_id} ->
        receive_stream(request_id, @maximum_response_bytes, @request_timeout)

      {:error, _reason} ->
        {:error, :network_error}
    end
  rescue
    _error in [ArgumentError, ErlangError, FunctionClauseError] ->
      {:error, :network_error}
  catch
    :exit, _reason -> {:error, :network_error}
  end

  def request(_method, _url, _headers, _body), do: {:error, :network_error}

  @doc false
  def receive_stream(request_id, maximum_bytes, timeout)
      when is_integer(maximum_bytes) and maximum_bytes > 0 and is_integer(timeout) and timeout > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout
    receive_stream_start(request_id, maximum_bytes, deadline)
  end

  defp receive_stream_start(request_id, maximum_bytes, deadline) do
    receive do
      {:http, {^request_id, :stream_start, headers, handler}} ->
        headers = normalize_headers(headers)

        if acceptable_success_headers?(headers, maximum_bytes) do
          stream_next(handler)
          receive_stream_body(request_id, handler, headers, [], 0, maximum_bytes, deadline)
        else
          cancel_request(request_id)
          {:error, :network_error}
        end

      {:http, {^request_id, {{_http_version, status, _reason}, headers, body}}}
      when is_integer(status) and is_binary(body) and byte_size(body) <= maximum_bytes ->
        {:ok, %{status: status, headers: normalize_headers(headers), body: body}}

      {:http, {^request_id, _error_or_oversized_response}} ->
        {:error, :network_error}
    after
      remaining_timeout(deadline) ->
        cancel_request(request_id)
        {:error, :network_error}
    end
  end

  defp receive_stream_body(
         request_id,
         handler,
         headers,
         chunks,
         received_bytes,
         maximum_bytes,
         deadline
       ) do
    receive do
      {:http, {^request_id, :stream, chunk}} when is_binary(chunk) ->
        received_bytes = received_bytes + byte_size(chunk)

        if received_bytes <= maximum_bytes do
          stream_next(handler)

          receive_stream_body(
            request_id,
            handler,
            headers,
            [chunk | chunks],
            received_bytes,
            maximum_bytes,
            deadline
          )
        else
          cancel_request(request_id)
          {:error, :network_error}
        end

      {:http, {^request_id, :stream_end, trailer_headers}} ->
        {:ok,
         %{
           status: 200,
           headers: Map.merge(headers, normalize_headers(trailer_headers)),
           body: chunks |> Enum.reverse() |> IO.iodata_to_binary()
         }}

      {:http, {^request_id, _stream_error}} ->
        {:error, :network_error}
    after
      remaining_timeout(deadline) ->
        cancel_request(request_id)
        {:error, :network_error}
    end
  end

  defp acceptable_success_headers?(headers, maximum_bytes) do
    not Map.has_key?(headers, "content-range") and
      case Map.get(headers, "content-length") do
        nil ->
          true

        content_length ->
          case Integer.parse(content_length) do
            {length, ""} -> length in 0..maximum_bytes
            _invalid -> false
          end
      end
  end

  defp remaining_timeout(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 0)
  end

  defp stream_next(handler) do
    :httpc.stream_next(handler)
  catch
    :exit, _reason -> :ok
  end

  defp cancel_request(request_id) do
    :httpc.cancel_request(request_id)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp normalize_headers(headers) do
    Map.new(headers, fn {name, value} ->
      {name |> normalize_header_part() |> String.downcase(), normalize_header_part(value)}
    end)
  end

  defp normalize_header_part(value) when is_binary(value), do: value
  defp normalize_header_part(value) when is_list(value), do: List.to_string(value)
end
