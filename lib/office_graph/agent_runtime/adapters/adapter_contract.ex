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
  @minimum_uuid "00000000-0000-0000-0000-000000000000"
  @common_input_field_types %{
    request_id: :uuid,
    execution_id: :uuid,
    step_key: :string,
    context_package_id: :uuid,
    authority_snapshot_id: :uuid,
    operation_id: :uuid,
    adapter_version: :string,
    idempotency_key: :string,
    capability_keys: {:list, :string},
    credential_kinds: {:list, :atom},
    sensitivity: {:enum, @sensitivities},
    approval_granted?: :boolean,
    timeout_ms: :positive_integer
  }

  def valid_model_manifest?(%ModelManifest{} = manifest), do: valid_manifest?(manifest, :model)
  def valid_model_manifest?(_manifest), do: false

  def valid_tool_manifest?(%ToolManifest{} = manifest), do: valid_manifest?(manifest, :tool)
  def valid_tool_manifest?(_manifest), do: false

  def validate_model_input(%ModelManifest{} = manifest, %ModelInput{} = input) do
    validate_input(manifest, input, :model)
  end

  def validate_model_input(_manifest, _input), do: {:error, {:terminal, :invalid_model_input}}

  def validate_model_preflight(%ModelManifest{} = manifest, %ModelInput{} = input) do
    validate_input(manifest, input, :model, skip_approval?: true)
  end

  def validate_model_preflight(_manifest, _input),
    do: {:error, {:terminal, :invalid_model_input}}

  def validate_tool_input(%ToolManifest{} = manifest, %ToolInput{} = input) do
    validate_input(manifest, input, :tool)
  end

  def validate_tool_input(_manifest, _input), do: {:error, {:terminal, :invalid_tool_input}}

  def validate_model_output(%ModelManifest{} = manifest, %ModelOutput{} = output) do
    validate_output(manifest, output, :model)
  end

  def validate_model_output(_manifest, _output), do: malformed_output(:model)

  def validate_tool_output(%ToolManifest{} = manifest, %ToolOutput{} = output) do
    validate_output(manifest, output, :tool)
  end

  def validate_tool_output(_manifest, _output), do: malformed_output(:tool)

  def input_schema_fields(kind, payload_schema)
      when kind in [:model, :tool] and is_map(payload_schema) do
    kind
    |> provider_neutral_field_types()
    |> Map.put(:adapter_payload, {:map, payload_schema})
  end

  def fingerprint(input) when is_struct(input) do
    input
    |> Map.from_struct()
    |> Map.delete(:request_id)
    |> canonicalize_authority_lists()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp valid_manifest?(manifest, kind) do
    is_binary(manifest.key) and manifest.key != "" and
      is_binary(manifest.version) and manifest.version != "" and
      valid_input_schema?(manifest.input_schema, manifest, kind) and
      valid_output_schema?(manifest.output_schema, manifest.output_classifications, kind) and
      valid_nonempty_string_list?(manifest.capability_keys) and
      valid_credential_kind_list?(manifest.credential_kinds) and
      manifest.sensitivity in @sensitivities and manifest.external_write == false and
      is_integer(manifest.timeout_ms) and manifest.timeout_ms in 1_000..120_000 and
      manifest.idempotency_supported == true and manifest.raw_retention == false and
      is_boolean(manifest.approval_required) and
      valid_classifications?(manifest.output_classifications, kind) and
      valid_budget?(manifest, kind)
  end

  defp validate_input(manifest, input, kind, opts \\ []) do
    checks =
      if opts[:skip_approval?],
        do:
          Enum.reject(
            input_checks(manifest, input, kind),
            &match?({_check, :approval_required}, &1)
          ),
        else: input_checks(manifest, input, kind)

    Enum.reduce_while(checks, :ok, fn {check, failure_code}, :ok ->
      if check.() do
        {:cont, :ok}
      else
        {:halt, {:error, {:terminal, failure_code}}}
      end
    end)
  end

  defp input_checks(manifest, input, kind) do
    invalid_input = invalid_input_code(kind)

    [
      {fn -> valid_manifest?(manifest, kind) end, invalid_input},
      {fn -> valid_input_fields?(input, kind) end, invalid_input},
      {fn -> schema_accepts?(manifest.input_schema, Map.from_struct(input)) end, invalid_input},
      {fn -> adapter_key(input, kind) == manifest.key end, invalid_input},
      {fn -> input.adapter_version == manifest.version end, invalid_input},
      {fn -> Enum.all?(manifest.capability_keys, &(&1 in input.capability_keys)) end,
       :missing_capability},
      {fn -> Enum.all?(manifest.credential_kinds, &(&1 in input.credential_kinds)) end,
       :missing_credential},
      {fn -> sensitivity_allowed?(input.sensitivity, manifest.sensitivity) end,
       :sensitivity_not_allowed},
      {fn -> not manifest.approval_required or input.approval_granted? end, :approval_required},
      {fn -> input.timeout_ms <= manifest.timeout_ms end, :timeout_exceeded},
      {fn -> budget(input, kind) <= manifest_budget(manifest, kind) end,
       budget_failure_code(kind)},
      {fn -> kind != :tool or input.external_write == false end, :external_write_forbidden}
    ]
  end

  defp validate_output(manifest, output, kind) do
    valid? =
      valid_manifest?(manifest, kind) and output_valid?(output, kind) and
        output.classification in manifest.output_classifications and
        schema_accepts?(manifest.output_schema, Map.from_struct(output)) and
        classified_content_valid?(manifest.output_schema, output)

    if valid?, do: :ok, else: malformed_output(kind)
  end

  defp valid_input_fields?(input, kind) do
    Enum.all?(request_identifiers(input), &match?({:ok, _uuid}, Ecto.UUID.cast(&1))) and
      valid_string_list?(input.capability_keys) and
      valid_credential_kind_list?(input.credential_kinds) and
      Enum.all?(
        [input.step_key, input.adapter_version, input.idempotency_key],
        &nonempty_string?/1
      ) and
      is_map(input.adapter_payload) and
      nonempty_string?(adapter_key(input, kind)) and input.sensitivity in @sensitivities and
      is_boolean(input.approval_granted?) and is_integer(input.timeout_ms) and
      input.timeout_ms > 0 and
      is_integer(budget(input, kind)) and budget(input, kind) > 0 and
      (kind != :tool or is_boolean(input.external_write))
  end

  defp output_valid?(output, :model), do: ModelOutput.valid?(output)
  defp output_valid?(output, :tool), do: ToolOutput.valid?(output)

  defp classified_content_valid?(schema, output) do
    with {:ok, content_schemas} <- Map.fetch(schema, :content_schemas),
         true <- is_map(content_schemas),
         content when is_map(content) <- output.structured_content,
         true <- map_size(content) == 1,
         content_key <- Atom.to_string(output.classification),
         {:ok, nested_content} <- Map.fetch(content, content_key),
         {:ok, content_schema} <- Map.fetch(content_schemas, output.classification) do
      schema_accepts?(content_schema, nested_content)
    else
      _invalid -> false
    end
  end

  defp valid_input_schema?(%{fields: fields} = schema, manifest, kind) when is_map(fields) do
    valid_schema?(schema) and input_field_types_compatible?(fields, kind) and
      minimum_input_envelope_fits?(schema, manifest, kind)
  end

  defp valid_input_schema?(_schema, _manifest, _kind), do: false

  defp valid_output_schema?(schema, classifications, kind) when is_map(schema) do
    content_schemas = Map.get(schema, :content_schemas)

    valid_schema?(schema) and
      schema.required == [:classification, :safe_summary, :structured_content] and
      schema.fields == %{
        classification: {:enum, classifications},
        safe_summary: {:string, 1_000},
        structured_content: :classified_content
      } and
      is_map(content_schemas) and
      valid_classifications?(classifications, kind) and
      Enum.all?(classifications, fn classification ->
        with {:ok, content_schema} <- Map.fetch(content_schemas, classification) do
          valid_schema?(content_schema) and
            minimum_output_envelope_fits?(schema, classification, content_schema)
        else
          :error -> false
        end
      end)
  end

  defp valid_output_schema?(_schema, _classifications, _kind), do: false

  defp valid_schema?(%{required: required, fields: fields, max_serialized_bytes: max_bytes}) do
    is_list(required) and is_map(fields) and Enum.all?(required, &Map.has_key?(fields, &1)) and
      is_integer(max_bytes) and max_bytes in 1..16_384 and
      Enum.all?(fields, fn {field, type} -> valid_field?(field) and valid_type?(type) end)
  end

  defp valid_schema?(_schema), do: false

  defp schema_accepts?(schema, value) when is_map(value) do
    serialized_size(value) <= schema.max_serialized_bytes and
      Enum.all?(schema.required, &(Map.get(value, &1) != nil)) and
      Enum.all?(Map.keys(value), &Map.has_key?(schema.fields, &1)) and
      Enum.all?(schema.fields, fn {field, type} ->
        not Map.has_key?(value, field) or valid_value?(Map.get(value, field), type)
      end)
  end

  defp schema_accepts?(_schema, _value), do: false

  defp valid_type?(:string), do: true
  defp valid_type?(:atom), do: true
  defp valid_type?(:boolean), do: true
  defp valid_type?(:uuid), do: true
  defp valid_type?(:positive_integer), do: true
  defp valid_type?(:classified_content), do: true
  defp valid_type?({:string, max_bytes}), do: is_integer(max_bytes) and max_bytes > 0
  defp valid_type?({:enum, values}), do: is_list(values) and values != []
  defp valid_type?({:list, type}), do: valid_type?(type)
  defp valid_type?({:map, schema}), do: valid_schema?(schema)
  defp valid_type?(_type), do: false

  defp valid_value?(value, :string), do: is_binary(value)
  defp valid_value?(value, :atom), do: is_atom(value)
  defp valid_value?(value, :boolean), do: is_boolean(value)
  defp valid_value?(value, :uuid), do: match?({:ok, _uuid}, Ecto.UUID.cast(value))
  defp valid_value?(value, :positive_integer), do: is_integer(value) and value > 0
  defp valid_value?(value, :classified_content), do: is_map(value)

  defp valid_value?(value, {:string, max_bytes}),
    do: is_binary(value) and byte_size(value) <= max_bytes

  defp valid_value?(value, {:enum, values}), do: value in values

  defp valid_value?(value, {:list, type}),
    do: is_list(value) and Enum.all?(value, &valid_value?(&1, type))

  defp valid_value?(value, {:map, schema}), do: schema_accepts?(schema, value)
  defp valid_value?(_value, _type), do: false

  defp serialized_size(value) do
    value |> :erlang.term_to_binary([:deterministic]) |> byte_size()
  rescue
    ArgumentError -> 16_385
  end

  defp valid_field?(field), do: is_atom(field) or is_binary(field)

  defp request_identifiers(input),
    do: [
      input.request_id,
      input.execution_id,
      input.context_package_id,
      input.authority_snapshot_id,
      input.operation_id
    ]

  defp input_field_types_compatible?(fields, kind) do
    with {:ok, {:map, payload_schema}} <- Map.fetch(fields, :adapter_payload),
         true <- valid_schema?(payload_schema) do
      Map.delete(fields, :adapter_payload) == provider_neutral_field_types(kind)
    else
      _incompatible -> false
    end
  end

  defp minimum_input_envelope_fits?(schema, manifest, kind) do
    with {:ok, {:map, payload_schema}} <- Map.fetch(schema.fields, :adapter_payload),
         {:ok, adapter_payload} <- minimum_schema_value(payload_schema) do
      schema_accepts?(schema, minimum_input_envelope(manifest, adapter_payload, kind))
    else
      _invalid_or_uninhabitable_schema -> false
    end
  end

  defp minimum_input_envelope(manifest, adapter_payload, kind) do
    common = %{
      request_id: @minimum_uuid,
      execution_id: @minimum_uuid,
      step_key: "x",
      context_package_id: @minimum_uuid,
      authority_snapshot_id: @minimum_uuid,
      operation_id: @minimum_uuid,
      adapter_version: manifest.version,
      idempotency_key: "x",
      capability_keys: manifest.capability_keys,
      credential_kinds: manifest.credential_kinds,
      sensitivity: :public,
      approval_granted?: true,
      timeout_ms: 1,
      adapter_payload: adapter_payload
    }

    case kind do
      :model ->
        Map.merge(common, %{adapter_key: manifest.key, token_budget: 1})

      :tool ->
        Map.merge(common, %{tool_key: manifest.key, budget_units: 1, external_write: false})
    end
  end

  defp minimum_output_envelope_fits?(schema, classification, content_schema) do
    with {:ok, content} <- minimum_schema_value(content_schema) do
      schema_accepts?(schema, %{
        classification: classification,
        safe_summary: "x",
        structured_content: %{Atom.to_string(classification) => content}
      })
    else
      :error -> false
    end
  end

  defp minimum_schema_value(%{required: required, fields: fields} = schema) do
    required
    |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, value} ->
      with {:ok, type} <- Map.fetch(fields, field),
           {:ok, minimum} <- minimum_value(type) do
        {:cont, {:ok, Map.put(value, field, minimum)}}
      else
        _invalid_type -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, value} -> if schema_accepts?(schema, value), do: {:ok, value}, else: :error
      :error -> :error
    end
  end

  defp minimum_value(:string), do: {:ok, ""}
  defp minimum_value(:atom), do: {:ok, :value}
  defp minimum_value(:boolean), do: {:ok, false}
  defp minimum_value(:uuid), do: {:ok, @minimum_uuid}
  defp minimum_value(:positive_integer), do: {:ok, 1}
  defp minimum_value(:classified_content), do: {:ok, %{}}
  defp minimum_value({:string, _max_bytes}), do: {:ok, ""}
  defp minimum_value({:enum, [value | _values]}), do: {:ok, value}
  defp minimum_value({:list, _type}), do: {:ok, []}
  defp minimum_value({:map, schema}), do: minimum_schema_value(schema)
  defp minimum_value(_type), do: :error

  defp provider_neutral_field_types(:model) do
    Map.merge(@common_input_field_types, %{
      adapter_key: :string,
      token_budget: :positive_integer
    })
  end

  defp provider_neutral_field_types(:tool) do
    Map.merge(@common_input_field_types, %{
      tool_key: :string,
      budget_units: :positive_integer,
      external_write: :boolean
    })
  end

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
  defp malformed_output(:model), do: {:error, {:terminal, :malformed_model_output}}
  defp malformed_output(:tool), do: {:error, {:terminal, :malformed_tool_output}}

  defp sensitivity_allowed?(requested, maximum),
    do: sensitivity_rank(requested) <= sensitivity_rank(maximum)

  defp sensitivity_rank(sensitivity), do: Enum.find_index(@sensitivities, &(&1 == sensitivity))

  defp canonicalize_authority_lists(input) do
    Enum.reduce([:capability_keys, :credential_kinds], input, fn field, normalized ->
      case Map.fetch(normalized, field) do
        {:ok, values} when is_list(values) ->
          Map.put(normalized, field, values |> Enum.uniq() |> Enum.sort())

        _missing_or_invalid ->
          normalized
      end
    end)
  end

  defp valid_string_list?(values), do: is_list(values) and Enum.all?(values, &nonempty_string?/1)

  defp valid_nonempty_string_list?(values), do: values != [] and valid_string_list?(values)

  defp valid_credential_kind_list?(values),
    do: is_list(values) and Enum.all?(values, &valid_credential_kind?/1)

  defp valid_credential_kind?(value),
    do: is_atom(value) and value not in [nil, false, true]

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
