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
    :completed_at
  ]
end
