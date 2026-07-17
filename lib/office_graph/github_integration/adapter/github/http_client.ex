defmodule OfficeGraph.GitHubIntegration.Adapter.GitHub.HTTPClient do
  @moduledoc false

  @callback request(
              method :: :get | :post | :patch,
              url :: String.t(),
              headers :: %{String.t() => String.t()},
              body :: String.t() | nil
            ) ::
              {:ok, %{status: pos_integer(), headers: map(), body: binary()}}
              | {:error, term()}
end

defmodule OfficeGraph.GitHubIntegration.Adapter.GitHub.HTTPClient.Httpc do
  @moduledoc false

  @behaviour OfficeGraph.GitHubIntegration.Adapter.GitHub.HTTPClient

  @impl true
  def request(method, url, headers, body) do
    request_headers =
      Enum.map(headers, fn {name, value} ->
        {String.to_charlist(name), String.to_charlist(value)}
      end)

    request =
      case method do
        :get ->
          {String.to_charlist(url), request_headers}

        method when method in [:post, :patch] ->
          {String.to_charlist(url), request_headers, ~c"application/json", body || ""}
      end

    case :httpc.request(
           method,
           request,
           [connect_timeout: 5_000, timeout: 15_000],
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
    _error -> {:error, :network_error}
  catch
    :exit, _reason -> {:error, :network_error}
  end

  defp normalize_headers(headers) do
    Map.new(headers, fn {name, value} ->
      {name |> List.to_string() |> String.downcase(), List.to_string(value)}
    end)
  end
end
