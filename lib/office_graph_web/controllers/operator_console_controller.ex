defmodule OfficeGraphWeb.OperatorConsoleController do
  use OfficeGraphWeb, :controller

  @react_router_asset_prefix "/assets/react-router/"
  @react_router_index_asset_path "/assets/react-router/index.html"
  @immutable_cache_control "public, max-age=31536000, immutable"

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
        |> put_resp_header("cache-control", @immutable_cache_control)
        |> send_file(200, file_path)

      :error ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp app_shell do
    with {:ok, html} <- File.read(react_router_index_path()),
         [] <- missing_assets(html) do
      {:ok, html}
    else
      {:error, _reason} -> {:error, [@react_router_index_asset_path]}
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

  defp react_router_index_path do
    Path.join(react_router_static_root(), "assets/react-router/index.html")
  end

  defp react_router_static_root do
    Application.get_env(:office_graph, :operator_console_static_root) ||
      Application.app_dir(:office_graph, "priv/static")
  end

  defp react_router_asset_file(@react_router_asset_prefix <> asset_name),
    do: static_asset_file(["react-router", asset_name])

  defp react_router_asset_file(path_segments) when is_list(path_segments) do
    case path_segments do
      ["react-router" | asset_segments] -> static_asset_file(["react-router" | asset_segments])
      _ -> :error
    end
  end

  defp react_router_asset_file(_asset_path), do: :error

  defp static_asset_file(path_segments) do
    static_root = Path.expand(react_router_static_root())
    file_path = Path.expand(Path.join(["assets" | path_segments]), static_root)

    if String.starts_with?(file_path, static_root <> "/") and File.regular?(file_path) do
      {:ok, file_path}
    else
      :error
    end
  end
end
