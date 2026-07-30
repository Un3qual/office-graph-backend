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
           [connect_timeout: @connect_timeout, timeout: @request_timeout],
           body_format: :binary
         ) do
      {:ok, {{_http_version, status, _reason}, response_headers, response_body}} ->
        {:ok,
         %{
           status: status,
           headers: normalize_headers(response_headers),
           body: response_body
         }}

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

  defp normalize_headers(headers) do
    Map.new(headers, fn {name, value} ->
      {name |> List.to_string() |> String.downcase(), List.to_string(value)}
    end)
  end
end
