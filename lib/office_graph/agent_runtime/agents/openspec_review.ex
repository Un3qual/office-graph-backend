defmodule OfficeGraph.AgentRuntime.Agents.OpenSpecReview do
  @moduledoc false

  @manifest %{
    definition_key: "openspec-review",
    external_write: false,
    tool_keys: ["repository.read", "openspec.read"]
  }

  def manifest, do: @manifest
end
