defmodule OfficeGraph.AgentRuntime.Tools.OpenSpecRead do
  @moduledoc false

  @behaviour OfficeGraph.AgentRuntime.ToolAdapter

  alias OfficeGraph.AgentRuntime.{
    AdapterContract,
    ToolInput,
    ToolManifest,
    ToolOutput
  }

  @version "1"
  @max_bytes 64 * 1_024
  @target_pattern ~r/\A[a-z0-9][a-z0-9._-]*\z/
  @revision_pattern ~r/\A[0-9a-f]{40}\z/

  @payload_schema AdapterContract.schema(
                    [:action, :revision],
                    %{
                      action: {:string, 32},
                      revision: {:string, 40},
                      target: {:string, 255}
                    },
                    1_024
                  )

  @observation_schema AdapterContract.schema(
                        ["subject", "reference", "content_hash", "byte_count"],
                        %{
                          "subject" => {:string, 1_000},
                          "reference" => {:string, 1_000},
                          "content_hash" => {:string, 64},
                          "byte_count" => :positive_integer
                        },
                        4_096
                      )

  @impl true
  def manifest do
    %ToolManifest{
      key: "openspec.read",
      version: @version,
      input_schema:
        AdapterContract.schema(
          [:adapter_payload],
          AdapterContract.input_schema_fields(:tool, @payload_schema),
          16_384
        ),
      output_schema: output_schema(),
      capability_keys: ["agent.tool.read", "openspec.read"],
      credential_kinds: [],
      sensitivity: :internal,
      external_write: false,
      timeout_ms: 10_000,
      budget_units: @max_bytes,
      output_classifications: [:observation],
      idempotency_supported: true,
      raw_retention: false,
      approval_required: false
    }
  end

  @impl true
  def invoke(%ToolInput{} = input) do
    with :ok <- AdapterContract.validate_tool_input(manifest(), input),
         :ok <- validate_revision(input.adapter_payload.revision),
         {:ok, argv, reference} <- command(input.adapter_payload),
         {:ok, content} <-
           execute(
             argv,
             input.adapter_payload.revision,
             input.timeout_ms,
             input.budget_units
           ),
         output <- output(reference, content),
         :ok <- AdapterContract.validate_tool_output(manifest(), output) do
      {:ok, output}
    end
  end

  def invoke(_input), do: {:error, {:terminal, :invalid_tool_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}

  @doc false
  def dereference(reference, timeout_ms, budget_units)
      when is_binary(reference) and is_integer(timeout_ms) and is_integer(budget_units) do
    with {:ok, payload} <- reference_payload(reference),
         :ok <- validate_revision(payload.revision),
         {:ok, argv, ^reference} <- command(payload) do
      execute(argv, payload.revision, timeout_ms, budget_units)
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, {:terminal, :invalid_openspec_reference}}
    end
  end

  def dereference(_reference, _timeout_ms, _budget_units),
    do: {:error, {:terminal, :invalid_openspec_reference}}

  defp reference_payload("openspec://" <> reference) do
    case String.split(reference, "/", parts: 3) do
      [revision, "list"] ->
        {:ok, %{action: "list", revision: revision}}

      [revision, action, target]
      when action in ["show", "status", "validate"] and target != "" ->
        {:ok, %{action: action, revision: revision, target: target}}

      _invalid ->
        {:error, {:terminal, :invalid_openspec_reference}}
    end
  end

  defp reference_payload(_reference),
    do: {:error, {:terminal, :invalid_openspec_reference}}

  defp command(%{action: "list", revision: revision} = payload) do
    if Enum.sort(Map.keys(payload)) == [:action, :revision] do
      {:ok, ["list", "--json"], "openspec://#{revision}/list"}
    else
      {:error, {:terminal, :invalid_openspec_target}}
    end
  end

  defp command(%{action: action, revision: revision, target: target})
       when action in ["show", "status", "validate"] do
    with :ok <- validate_target(target) do
      case action do
        "show" ->
          {:ok, ["show", target, "--json"], "openspec://#{revision}/show/#{target}"}

        "status" ->
          {:ok, ["status", "--change", target, "--json"],
           "openspec://#{revision}/status/#{target}"}

        "validate" ->
          {:ok, ["validate", target, "--strict"], "openspec://#{revision}/validate/#{target}"}
      end
    end
  end

  defp command(%{action: action}) when action in ["show", "status", "validate"],
    do: {:error, {:terminal, :invalid_openspec_target}}

  defp command(%{action: _unsupported}),
    do: {:error, {:terminal, :unsupported_openspec_action}}

  defp command(_payload), do: {:error, {:terminal, :invalid_tool_input}}

  defp validate_target(target) when is_binary(target) do
    if Regex.match?(@target_pattern, target),
      do: :ok,
      else: {:error, {:terminal, :invalid_openspec_target}}
  end

  defp validate_target(_target), do: {:error, {:terminal, :invalid_openspec_target}}

  defp validate_revision(revision) when is_binary(revision) do
    if Regex.match?(@revision_pattern, revision),
      do: :ok,
      else: {:error, {:terminal, :invalid_openspec_revision}}
  end

  defp validate_revision(_revision),
    do: {:error, {:terminal, :invalid_openspec_revision}}

  defp execute(argv, revision, timeout_ms, requested_budget) do
    byte_limit = min(requested_budget, @max_bytes)

    with :ok <- validate_current_revision(revision, timeout_ms) do
      case command_runner().run(openspec_executable(), argv,
             cd: repository_root(),
             environment: %{"OPENSPEC_TELEMETRY" => "0"},
             timeout_ms: timeout_ms,
             max_bytes: byte_limit
           ) do
        {:ok, content} when byte_size(content) > 0 ->
          {:ok, content}

        {:error, :output_limit_exceeded} ->
          {:error, {:terminal, :openspec_read_limit_exceeded}}

        {:ok, _empty_content} ->
          {:error, {:terminal, :openspec_read_failed}}

        {:error, _reason} ->
          {:error, {:terminal, :openspec_read_failed}}
      end
    end
  end

  defp validate_current_revision(expected, timeout_ms) do
    case command_runner().run(
           git_executable(),
           ["-C", repository_root(), "rev-parse", "HEAD"],
           timeout_ms: timeout_ms,
           max_bytes: 128
         ) do
      {:ok, revision} ->
        if String.trim(revision) == expected,
          do: :ok,
          else: {:error, {:terminal, :openspec_repository_revision_changed}}

      {:error, _reason} ->
        {:error, {:terminal, :openspec_repository_revision_changed}}
    end
  end

  defp output(reference, content) do
    %ToolOutput{
      classification: :observation,
      safe_summary: "Read authorized OpenSpec reference #{reference}",
      structured_content: %{
        "observation" => %{
          "subject" => "authorized_openspec_context",
          "reference" => reference,
          "content_hash" => digest(content),
          "byte_count" => byte_size(content)
        }
      }
    }
  end

  defp output_schema do
    AdapterContract.output_schema([:observation], %{observation: @observation_schema})
  end

  defp repository_root do
    tooling_config() |> Keyword.fetch!(:repository_root)
  end

  defp git_executable, do: tooling_config() |> Keyword.fetch!(:git_executable)

  defp openspec_executable, do: tooling_config() |> Keyword.fetch!(:openspec_executable)

  defp tooling_config,
    do: Application.fetch_env!(:office_graph, :agent_runtime_repository_tooling)

  defp command_runner do
    Application.get_env(
      :office_graph,
      :agent_runtime_command_runner,
      OfficeGraph.AgentRuntime.Tools.CommandRunner
    )
  end

  defp digest(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
