defmodule OfficeGraph.AgentRuntime.AdapterContract do
  @moduledoc false

  alias OfficeGraph.AgentRuntime.{
    ModelInput,
    ModelManifest,
    ModelOutput,
    ToolInput,
    ToolManifest,
    ToolOutput
  }

  @sensitivities [:public, :internal, :confidential, :restricted]

  def valid_model_manifest?(%ModelManifest{} = manifest), do: valid_manifest?(manifest, :model)
  def valid_model_manifest?(_manifest), do: false

  def valid_tool_manifest?(%ToolManifest{} = manifest), do: valid_manifest?(manifest, :tool)
  def valid_tool_manifest?(_manifest), do: false

  def validate_model_input(%ModelManifest{} = manifest, %ModelInput{} = input) do
    validate_input(manifest, input, :model)
  end

  def validate_model_input(_manifest, _input), do: {:error, {:terminal, :invalid_model_input}}

  def validate_tool_input(%ToolManifest{} = manifest, %ToolInput{} = input) do
    validate_input(manifest, input, :tool)
  end

  def validate_tool_input(_manifest, _input), do: {:error, {:terminal, :invalid_tool_input}}

  def fingerprint(input) when is_struct(input) do
    input
    |> Map.from_struct()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp valid_manifest?(manifest, kind) do
    is_binary(manifest.key) and manifest.key != "" and
      is_binary(manifest.version) and manifest.version != "" and
      valid_schema?(manifest.input_schema) and valid_schema?(manifest.output_schema) and
      valid_string_list?(manifest.capability_keys) and valid_atom_list?(manifest.credential_kinds) and
      manifest.sensitivity in @sensitivities and manifest.external_write == false and
      is_integer(manifest.timeout_ms) and manifest.timeout_ms in 1_000..120_000 and
      is_boolean(manifest.idempotency_supported) and manifest.raw_retention == false and
      is_boolean(manifest.approval_required) and
      valid_classifications?(manifest.output_classifications, kind) and
      valid_budget?(manifest, kind)
  end

  defp validate_input(manifest, input, kind) do
    with true <- valid_manifest?(manifest, kind),
         true <- valid_input_fields?(input, kind),
         true <- adapter_key(input, kind) == manifest.key,
         true <- input.adapter_version == manifest.version,
         true <- Enum.all?(manifest.capability_keys, &(&1 in input.capability_keys)),
         true <- Enum.all?(manifest.credential_kinds, &(&1 in input.credential_kinds)),
         true <- sensitivity_allowed?(input.sensitivity, manifest.sensitivity),
         true <- not manifest.approval_required or input.approval_granted?,
         true <- input.timeout_ms <= manifest.timeout_ms,
         true <- budget(input, kind) <= manifest_budget(manifest, kind),
         true <- kind != :tool or input.external_write == false do
      :ok
    else
      false -> input_failure(manifest, input, kind)
    end
  end

  defp input_failure(manifest, input, kind) do
    cond do
      not valid_manifest?(manifest, kind) ->
        {:error, {:terminal, invalid_input_code(kind)}}

      not valid_input_fields?(input, kind) ->
        {:error, {:terminal, invalid_input_code(kind)}}

      adapter_key(input, kind) != manifest.key ->
        {:error, {:terminal, invalid_input_code(kind)}}

      input.adapter_version != manifest.version ->
        {:error, {:terminal, invalid_input_code(kind)}}

      not Enum.all?(manifest.capability_keys, &(&1 in input.capability_keys)) ->
        {:error, {:terminal, :missing_capability}}

      not Enum.all?(manifest.credential_kinds, &(&1 in input.credential_kinds)) ->
        {:error, {:terminal, :missing_credential}}

      not sensitivity_allowed?(input.sensitivity, manifest.sensitivity) ->
        {:error, {:terminal, :sensitivity_not_allowed}}

      manifest.approval_required and not input.approval_granted? ->
        {:error, {:terminal, :approval_required}}

      input.timeout_ms > manifest.timeout_ms ->
        {:error, {:terminal, :timeout_exceeded}}

      budget(input, kind) > manifest_budget(manifest, kind) ->
        {:error, {:terminal, budget_failure_code(kind)}}

      kind == :tool and input.external_write ->
        {:error, {:terminal, :external_write_forbidden}}
    end
  end

  defp valid_input_fields?(input, kind) do
    Enum.all?(request_identifiers(input), &match?({:ok, _uuid}, Ecto.UUID.cast(&1))) and
      valid_string_list?(input.capability_keys) and valid_atom_list?(input.credential_kinds) and
      Enum.all?(
        [input.adapter_version, input.idempotency_key, input.fixture_id],
        &nonempty_string?/1
      ) and
      nonempty_string?(adapter_key(input, kind)) and input.sensitivity in @sensitivities and
      is_boolean(input.approval_granted?) and is_integer(input.timeout_ms) and
      input.timeout_ms > 0 and
      is_integer(budget(input, kind)) and budget(input, kind) > 0 and
      (kind != :tool or is_boolean(input.external_write))
  end

  defp request_identifiers(input),
    do: [
      input.request_id,
      input.execution_id,
      input.context_package_id,
      input.authority_snapshot_id,
      input.operation_id
    ]

  defp adapter_key(input, :model), do: input.adapter_key
  defp adapter_key(input, :tool), do: input.tool_key
  defp budget(input, :model), do: input.token_budget
  defp budget(input, :tool), do: input.budget_units
  defp manifest_budget(manifest, :model), do: manifest.token_budget
  defp manifest_budget(manifest, :tool), do: manifest.budget_units
  defp invalid_input_code(:model), do: :invalid_model_input
  defp invalid_input_code(:tool), do: :invalid_tool_input
  defp budget_failure_code(:model), do: :token_budget_exceeded
  defp budget_failure_code(:tool), do: :budget_exceeded

  defp sensitivity_allowed?(requested, maximum),
    do: sensitivity_rank(requested) <= sensitivity_rank(maximum)

  defp sensitivity_rank(sensitivity), do: Enum.find_index(@sensitivities, &(&1 == sensitivity))
  defp valid_schema?(schema), do: is_map(schema) and map_size(schema) > 0
  defp valid_string_list?(values), do: is_list(values) and Enum.all?(values, &nonempty_string?/1)
  defp valid_atom_list?(values), do: is_list(values) and Enum.all?(values, &is_atom/1)
  defp nonempty_string?(value), do: is_binary(value) and value != ""

  defp valid_classifications?(classifications, :model),
    do:
      is_list(classifications) and classifications != [] and
        Enum.all?(classifications, &(&1 in ModelOutput.classifications()))

  defp valid_classifications?(classifications, :tool),
    do:
      is_list(classifications) and classifications != [] and
        Enum.all?(classifications, &(&1 in ToolOutput.classifications()))

  defp valid_budget?(manifest, :model),
    do: is_integer(manifest.token_budget) and manifest.token_budget > 0

  defp valid_budget?(manifest, :tool),
    do: is_integer(manifest.budget_units) and manifest.budget_units > 0
end
