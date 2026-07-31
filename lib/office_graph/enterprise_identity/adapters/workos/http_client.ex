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

defmodule OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.HTTPClient.ReqClient do
  @moduledoc false

  @behaviour OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.HTTPClient

  @connect_timeout 5_000
  @request_timeout 15_000
  @maximum_response_bytes 1_000_000
  @received_bytes_key :office_graph_received_bytes
  @response_too_large_key :office_graph_response_too_large

  @impl true
  def request(method, url, headers, body) when method in [:get, :post] do
    Req.request(
      method: method,
      url: url,
      headers: Map.to_list(headers),
      body: body,
      connect_options: [timeout: @connect_timeout],
      request_timeout: @request_timeout,
      receive_timeout: @request_timeout,
      retry: false,
      redirect: false,
      raw: true,
      into: bounded_collector(@maximum_response_bytes)
    )
    |> normalize_response()
  rescue
    _error in [ArgumentError, ErlangError, FunctionClauseError] ->
      {:error, :network_error}
  catch
    :exit, _reason -> {:error, :network_error}
  end

  def request(_method, _url, _headers, _body), do: {:error, :network_error}

  defp bounded_collector(maximum_bytes) do
    fn {:data, chunk}, {request, response} ->
      received_bytes =
        Req.Response.get_private(response, @received_bytes_key, 0) + byte_size(chunk)

      if received_bytes <= maximum_bytes and
           declared_length_within_limit?(response, maximum_bytes) do
        chunks = if response.body == "", do: [], else: response.body

        response =
          response
          |> Map.replace!(:body, [chunk | chunks])
          |> Req.Response.put_private(@received_bytes_key, received_bytes)

        {:cont, {request, response}}
      else
        response =
          response
          |> Map.replace!(:body, :response_too_large)
          |> Req.Response.put_private(@response_too_large_key, true)

        {:halt, {request, response}}
      end
    end
  end

  defp declared_length_within_limit?(response, maximum_bytes) do
    case Req.Response.get_header(response, "content-length") do
      [] ->
        true

      [content_length] ->
        case Integer.parse(content_length) do
          {length, ""} -> length in 0..maximum_bytes
          _invalid -> false
        end

      _duplicate_lengths ->
        false
    end
  end

  defp normalize_response({:ok, response}) do
    if Req.Response.get_private(response, @response_too_large_key, false) do
      {:error, :network_error}
    else
      body =
        case response.body do
          "" -> ""
          chunks when is_list(chunks) -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
        end

      headers = response |> Req.Response.to_map() |> Map.fetch!(:headers) |> Map.new()

      {:ok, %{status: response.status, headers: headers, body: body}}
    end
  end

  defp normalize_response({:error, _reason}), do: {:error, :network_error}
end
