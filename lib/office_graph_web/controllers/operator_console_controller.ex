defmodule OfficeGraphWeb.OperatorConsoleController do
  use OfficeGraphWeb, :controller

  @react_router_build_root Path.expand("../../../assets/build/client", __DIR__)
  @react_router_assets_root Path.join(@react_router_build_root, "assets")
  @react_router_index_path Path.join(@react_router_build_root, "index.html")

  def index(conn, _params) do
    case app_shell() do
      {:ok, html} ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, html)

      {:error, missing_assets} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(
          503,
          "Operator console assets are missing: #{Enum.join(missing_assets, ", ")}"
        )
    end
  end

  def asset(conn, %{"path" => path}) do
    case react_router_asset_file(path) do
      {:ok, file_path} ->
        conn
        |> put_resp_content_type(MIME.from_path(file_path))
        |> send_file(200, file_path)

      :error ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp app_shell do
    with {:ok, html} <- File.read(@react_router_index_path),
         [] <- missing_assets(html) do
      {:ok, html}
    else
      {:error, _reason} -> {:error, ["assets/build/client/index.html"]}
      missing_assets when is_list(missing_assets) -> {:error, missing_assets}
    end
  end

  defp missing_assets(html) do
    html
    |> react_router_asset_paths()
    |> include_manifest_assets()
    |> Enum.reject(fn asset_path ->
      match?({:ok, _file_path}, react_router_asset_file(asset_path))
    end)
  end

  defp include_manifest_assets(asset_paths) do
    manifest_assets =
      asset_paths
      |> Enum.filter(&String.contains?(&1, "manifest-"))
      |> Enum.flat_map(&manifest_asset_paths/1)

    Enum.uniq(asset_paths ++ manifest_assets)
  end

  defp manifest_asset_paths(asset_path) do
    with {:ok, file_path} <- react_router_asset_file(asset_path),
         {:ok, manifest} <- File.read(file_path) do
      react_router_asset_paths(manifest)
    else
      _ -> []
    end
  end

  defp react_router_asset_paths(source) do
    ~r{/assets/[^"'\s<>)]+}
    |> Regex.scan(source)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp react_router_asset_file("/assets/" <> asset_name),
    do: react_router_asset_file([asset_name])

  defp react_router_asset_file(path_segments) when is_list(path_segments) do
    relative_path = Path.join(path_segments)
    file_path = Path.expand(relative_path, @react_router_assets_root)
    assets_root = Path.expand(@react_router_assets_root)

    if String.starts_with?(file_path, assets_root <> "/") and File.regular?(file_path) do
      {:ok, file_path}
    else
      :error
    end
  end

  defp react_router_asset_file(_asset_path), do: :error
end
