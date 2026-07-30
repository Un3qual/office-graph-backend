defmodule OfficeGraph.AgentRuntime.ReferenceCatalog do
  @moduledoc false

  @run_review %{
    key: "run-review",
    name: "Run Review",
    description: "Reviews authorized Office Graph run context and proposes bounded follow-up.",
    lifecycle_state: "active",
    supported_modes: ["human", "automatic"],
    requested_capabilities: [
      "agent.invoke",
      "agent.model.generate",
      "proposal.create",
      "evidence.suggest"
    ],
    model_adapter_key: "deterministic",
    tool_allowlist: [],
    default_autonomy_mode: "human_supervised",
    allowed_output_kinds: [
      "message",
      "finding",
      "proposal",
      "observation",
      "evidence_candidate"
    ]
  }

  def definitions, do: [@run_review]
end
