defmodule OfficeGraphWeb.GraphQL.RelayIdTranslator do
  @moduledoc false

  @behaviour Absinthe.Relay.Node.IDTranslator

  alias Absinthe.Relay.Node.IDTranslator.Base64

  @impl true
  def to_global_id(type_name, source_id, schema) do
    Base64.to_global_id(type_name, source_id, schema)
  end

  @impl true
  def from_global_id(global_id, schema) do
    with {:ok, type_name, source_id} <- Base64.from_global_id(global_id, schema) do
      {:ok, normalize_type_name(type_name), source_id}
    end
  end

  defp normalize_type_name("signal"), do: "Signal"
  defp normalize_type_name("work_packet"), do: "WorkPacket"
  defp normalize_type_name("work_run"), do: "WorkRun"
  defp normalize_type_name(type_name), do: type_name
end
