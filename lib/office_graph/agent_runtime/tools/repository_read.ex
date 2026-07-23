defmodule OfficeGraph.AgentRuntime.Tools.RepositoryRead do
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
  @default_allowlist ["openspec/project.md", "openspec/specs", "openspec/changes"]
  @revision_pattern ~r/\A[0-9a-f]{40}\z/

  @payload_schema %{
    required: [:path, :revision],
    fields: %{path: {:string, 1_024}, revision: {:string, 40}},
    max_serialized_bytes: 2_048
  }

  @observation_schema %{
    required: ["subject", "reference", "content_hash", "byte_count"],
    fields: %{
      "subject" => {:string, 1_000},
      "reference" => {:string, 2_048},
      "content_hash" => {:string, 64},
      "byte_count" => :positive_integer
    },
    max_serialized_bytes: 4_096
  }

  @impl true
  def manifest do
    %ToolManifest{
      key: "repository.read",
      version: @version,
      input_schema: %{
        required: [:adapter_payload],
        fields: AdapterContract.input_schema_fields(:tool, @payload_schema),
        max_serialized_bytes: 16_384
      },
      output_schema: output_schema(),
      capability_keys: ["agent.tool.read", "repository.read"],
      credential_kinds: [],
      sensitivity: :internal,
      external_write: false,
      timeout_ms: 5_000,
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
         {:ok, path} <- canonical_path(input.adapter_payload.path),
         :ok <- validate_revision(input.adapter_payload.revision),
         :ok <- validate_allowlist(path),
         {:ok, content} <-
           read_revision(
             path,
             input.adapter_payload.revision,
             input.timeout_ms,
             input.budget_units
           ),
         output <- output(path, input.adapter_payload.revision, content),
         :ok <- AdapterContract.validate_tool_output(manifest(), output) do
      {:ok, output}
    end
  end

  def invoke(_input), do: {:error, {:terminal, :invalid_tool_input}}

  @impl true
  def cancel(_request_id), do: {:error, :not_found}

  def pinned_revision do
    case command("git", ["-C", repository_root(), "rev-parse", "HEAD"],
           timeout_ms: 5_000,
           max_bytes: 128
         ) do
      {:ok, revision} ->
        revision = String.trim(revision)

        case validate_revision(revision) do
          :ok -> {:ok, revision}
          {:error, _reason} = error -> error
        end

      {:error, _reason} = error ->
        error
    end
  end

  @doc false
  def dereference(reference, timeout_ms, budget_units)
      when is_binary(reference) and is_integer(timeout_ms) and is_integer(budget_units) do
    with {:ok, revision, path} <- parse_reference(reference),
         :ok <- validate_revision(revision),
         {:ok, canonical_path} <- canonical_path(path),
         true <- canonical_path == path,
         :ok <- validate_allowlist(canonical_path) do
      read_revision(canonical_path, revision, timeout_ms, budget_units)
    else
      false -> {:error, {:terminal, :repository_reference_invalid}}
      {:error, _reason} = error -> error
    end
  end

  def dereference(_reference, _timeout_ms, _budget_units),
    do: {:error, {:terminal, :repository_reference_invalid}}

  defp parse_reference("repository://" <> reference) do
    case String.split(reference, "/", parts: 2) do
      [revision, path] when path != "" -> {:ok, revision, path}
      _invalid -> {:error, {:terminal, :repository_reference_invalid}}
    end
  end

  defp parse_reference(_reference),
    do: {:error, {:terminal, :repository_reference_invalid}}

  defp canonical_path(path) when is_binary(path) do
    parts = Path.split(path)

    if Path.type(path) == :relative and parts != [] and
         Enum.all?(parts, &valid_path_part?/1) do
      {:ok, Enum.join(parts, "/")}
    else
      {:error, {:terminal, :repository_path_forbidden}}
    end
  end

  defp canonical_path(_path), do: {:error, {:terminal, :repository_path_forbidden}}

  defp valid_path_part?(part) do
    part not in ["", ".", ".."] and Regex.match?(~r/\A[a-zA-Z0-9._-]+\z/, part)
  end

  defp validate_revision(revision) when is_binary(revision) do
    if Regex.match?(@revision_pattern, revision),
      do: :ok,
      else: {:error, {:terminal, :repository_revision_invalid}}
  end

  defp validate_revision(_revision),
    do: {:error, {:terminal, :repository_revision_invalid}}

  defp validate_allowlist(path) do
    allowed? =
      Enum.any?(repository_allowlist(), fn allowed ->
        path == allowed or String.starts_with?(path, allowed <> "/")
      end)

    if allowed?, do: :ok, else: {:error, {:terminal, :repository_path_forbidden}}
  end

  defp read_revision(path, revision, timeout_ms, requested_budget) do
    object = "#{revision}:#{path}"
    byte_limit = min(requested_budget, @max_bytes)

    with {:ok, size_text} <-
           command("git", ["-C", repository_root(), "cat-file", "-s", object],
             timeout_ms: timeout_ms,
             max_bytes: 128
           ),
         {size, ""} <- size_text |> String.trim() |> Integer.parse(),
         true <- size > 0 and size <= byte_limit,
         {:ok, content} <-
           command("git", ["-C", repository_root(), "show", object],
             timeout_ms: timeout_ms,
             max_bytes: byte_limit
           ),
         true <- byte_size(content) == size do
      {:ok, content}
    else
      false ->
        {:error, {:terminal, :repository_read_limit_exceeded}}

      :error ->
        {:error, {:terminal, :repository_read_failed}}

      {:error, :output_limit_exceeded} ->
        {:error, {:terminal, :repository_read_limit_exceeded}}

      {:error, _reason} ->
        {:error, {:terminal, :repository_read_failed}}
    end
  end

  defp output(path, revision, content) do
    content_hash = digest(content)

    %ToolOutput{
      classification: :observation,
      safe_summary: "Read pinned repository reference #{path}",
      structured_content: %{
        "observation" => %{
          "subject" => "authorized_repository_context",
          "reference" => "repository://#{revision}/#{path}",
          "content_hash" => content_hash,
          "byte_count" => byte_size(content)
        }
      }
    }
  end

  defp output_schema do
    %{
      required: [:classification, :safe_summary, :structured_content],
      fields: %{
        classification: {:enum, [:observation]},
        safe_summary: {:string, 1_000},
        structured_content: :classified_content
      },
      content_schemas: %{observation: @observation_schema},
      max_serialized_bytes: 16_384
    }
  end

  defp command(executable, argv, opts), do: command_runner().run(executable, argv, opts)

  defp command_runner do
    Application.get_env(
      :office_graph,
      :agent_runtime_command_runner,
      OfficeGraph.AgentRuntime.Tools.CommandRunner
    )
  end

  defp repository_root do
    :office_graph
    |> Application.get_env(:agent_runtime_repository_root, File.cwd!())
    |> Path.expand()
  end

  defp repository_allowlist do
    Application.get_env(:office_graph, :agent_runtime_repository_allowlist, @default_allowlist)
  end

  defp digest(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
