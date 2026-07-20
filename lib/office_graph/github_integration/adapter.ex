defmodule OfficeGraph.GitHubIntegration.Adapter do
  @moduledoc """
  Provider boundary used by reconciliation and the two explicitly supported outbound actions.

  Review-reply adapters use the durable outbound action ID in `:idempotency_key` as a provider
  marker. `find_review_reply/2` must reconcile that marker before `reply_to_review/2` performs
  the non-idempotent create.
  """

  @callback fetch(request :: struct()) :: {:ok, struct()} | {:error, term()}
  @callback find_review_reply(request :: map(), credential :: String.t()) ::
              {:ok, map() | nil} | {:error, term()}
  @callback reply_to_review(request :: map(), credential :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback update_check(request :: map(), credential :: String.t()) ::
              {:ok, map()} | {:error, term()}
end

defmodule OfficeGraph.GitHubIntegration.Adapter.ReconciliationSnapshot do
  @moduledoc "Normalized authoritative state returned by a provider adapter."

  @enforce_keys [:provider_version, :provider_sequence, :repository, :pull_request]
  defstruct [
    :provider_version,
    :provider_sequence,
    :provider_updated_at,
    :repository,
    :pull_request,
    review_threads: [],
    review_comments: [],
    check_runs: []
  ]
end

defmodule OfficeGraph.GitHubIntegration.Adapter.RepositorySnapshot do
  @moduledoc false
  @enforce_keys [:node_id, :name, :full_name, :owner_login, :visibility]
  defstruct [
    :node_id,
    :database_id,
    :provider_version,
    :provider_sequence,
    :provider_updated_at,
    :name,
    :full_name,
    :owner_login,
    :default_ref_name,
    :visibility,
    :url
  ]
end

defmodule OfficeGraph.GitHubIntegration.Adapter.PullRequestSnapshot do
  @moduledoc false
  @enforce_keys [:node_id, :number, :title, :state, :is_draft]
  defstruct [
    :node_id,
    :database_id,
    :number,
    :title,
    :body,
    :state,
    :is_draft,
    :author_label,
    :url,
    :opened_at,
    :closed_at,
    :merged_at
  ]
end

defmodule OfficeGraph.GitHubIntegration.Adapter.ProviderMetadata do
  @moduledoc false
  @enforce_keys [:version, :sequence, :updated_at]
  defstruct [:version, :sequence, :updated_at]
end

defmodule OfficeGraph.GitHubIntegration.Adapter.ReviewThreadSnapshot do
  @moduledoc false
  @enforce_keys [:node_id, :state]
  defstruct [:node_id, :state, :path, :line, :side, :resolved_at]
end

defmodule OfficeGraph.GitHubIntegration.Adapter.ReviewCommentSnapshot do
  @moduledoc false
  @enforce_keys [:node_id, :body, :state]
  defstruct [
    :node_id,
    :database_id,
    :review_database_id,
    :review_thread_node_id,
    :parent_comment_node_id,
    :provider_version,
    :provider_sequence,
    :provider_updated_at,
    :body,
    :author_label,
    :state,
    :published_at,
    :url
  ]
end

defmodule OfficeGraph.GitHubIntegration.Adapter.CheckRunSnapshot do
  @moduledoc false
  @enforce_keys [:node_id, :name, :status]
  defstruct [
    :node_id,
    :database_id,
    :check_suite_database_id,
    :provider_version,
    :provider_sequence,
    :provider_updated_at,
    :name,
    :status,
    :conclusion,
    :details_url,
    :started_at,
    :completed_at,
    current?: true
  ]
end

defmodule OfficeGraph.GitHubIntegration.Adapter.ProviderDigest do
  @moduledoc false

  alias OfficeGraph.GitHubIntegration.Adapter.{CheckRunSnapshot, RepositorySnapshot}

  def repository(%RepositorySnapshot{} = repository) do
    digest("github-repository:v1", [
      repository.node_id,
      repository.database_id,
      repository.name,
      repository.full_name,
      repository.owner_login,
      repository.default_ref_name,
      repository.visibility,
      repository.url
    ])
  end

  def check_run(%CheckRunSnapshot{} = check) do
    digest("github-check:v2", [
      check.node_id,
      check.database_id,
      check.check_suite_database_id,
      check.name,
      check.status,
      check.conclusion,
      check.details_url,
      check.started_at,
      check.completed_at
    ])
  end

  defp digest(prefix, values) do
    digest =
      values
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    "#{prefix}:#{digest}"
  end
end
