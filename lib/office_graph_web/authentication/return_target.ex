defmodule OfficeGraphWeb.Authentication.ReturnTarget do
  @moduledoc false

  @default "/operator"

  def safe(return_to) when is_binary(return_to) do
    decoded_return_to = fully_decode(return_to)

    if String.valid?(return_to) and String.valid?(decoded_return_to) and
         root_relative?(return_to) and root_relative?(decoded_return_to) do
      return_to
    else
      @default
    end
  end

  def safe(_return_to), do: @default

  defp root_relative?(return_to) do
    uri = URI.parse(return_to)

    uri.scheme == nil and uri.host == nil and String.starts_with?(return_to, "/") and
      not String.starts_with?(return_to, "//") and
      not Regex.match?(~r/[\\\x00-\x1F\x7F]/u, return_to)
  end

  defp fully_decode(value) do
    case URI.decode(value) do
      ^value -> value
      decoded -> fully_decode(decoded)
    end
  end
end
