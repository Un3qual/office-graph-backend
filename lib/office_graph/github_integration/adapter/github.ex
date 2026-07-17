defmodule OfficeGraph.GitHubIntegration.Adapter.GitHub do
  @moduledoc """
  Live GitHub App adapter for authoritative reconciliation and the two supported writes.

  The adapter exchanges the configured App identity and bound installation private key for a
  short-lived installation token. Tokens are cached only in memory and never persisted.
  """

  @behaviour OfficeGraph.GitHubIntegration.Adapter

  alias OfficeGraph.GitHubIntegration.Adapter

  @max_comment_pages 100
  @max_snapshot_pages 100

  @resolve_query """
  query OfficeGraphResolveObject($id: ID!) {
    node(id: $id) {
      __typename
      ... on PullRequest {
        id
      }
      ... on PullRequestReviewComment {
        pullRequest { id }
      }
      ... on CheckRun {
        checkSuite {
          pullRequests(first: 1) { nodes { id } }
        }
      }
    }
  }
  """

  @pull_request_query """
  query OfficeGraphPullRequestSnapshot($id: ID!) {
    node(id: $id) {
      ... on PullRequest {
        id
        databaseId
        number
        title
        body
        state
        isDraft
        updatedAt
        createdAt
        closedAt
        mergedAt
        url
        author { login }
        repository {
          id
          databaseId
          name
          nameWithOwner
          visibility
          url
          owner { login }
          defaultBranchRef { name }
        }
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            isOutdated
            path
            line
            diffSide
            comments(first: 100) {
              nodes {
                id
                databaseId
                body
                state
                isMinimized
                createdAt
                updatedAt
                url
                author { login }
                replyTo { id }
                pullRequestReview { databaseId }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
          pageInfo { hasNextPage endCursor }
        }
        commits(last: 1) {
          nodes {
            commit {
              statusCheckRollup {
                contexts(first: 100) {
                  nodes {
                    __typename
                    ... on CheckRun {
                      id
                      databaseId
                      checkSuite { databaseId }
                      name
                      status
                      conclusion
                      detailsUrl
                      startedAt
                      completedAt
                    }
                  }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
          }
        }
      }
    }
  }
  """

  @outbound_context_query """
  query OfficeGraphOutboundTarget($id: ID!) {
    node(id: $id) {
      ... on PullRequestReviewComment {
        databaseId
        pullRequest {
          number
          repository { nameWithOwner }
        }
      }
      ... on CheckRun {
        databaseId
        checkSuite {
          repository { nameWithOwner }
        }
      }
    }
  }
  """

  @review_threads_page_query """
  query OfficeGraphReviewThreadsPage($id: ID!, $cursor: String!) {
    node(id: $id) {
      ... on PullRequest {
        reviewThreads(first: 100, after: $cursor) {
          nodes {
            id
            isResolved
            isOutdated
            path
            line
            diffSide
            comments(first: 100) {
              nodes {
                id
                databaseId
                body
                state
                isMinimized
                createdAt
                updatedAt
                url
                author { login }
                replyTo { id }
                pullRequestReview { databaseId }
              }
              pageInfo { hasNextPage endCursor }
            }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }
  """

  @thread_comments_page_query """
  query OfficeGraphReviewThreadCommentsPage($id: ID!, $cursor: String!) {
    node(id: $id) {
      ... on PullRequestReviewThread {
        comments(first: 100, after: $cursor) {
          nodes {
            id
            databaseId
            body
            state
            isMinimized
            createdAt
            updatedAt
            url
            author { login }
            replyTo { id }
            pullRequestReview { databaseId }
          }
          pageInfo { hasNextPage endCursor }
        }
      }
    }
  }
  """

  @check_runs_page_query """
  query OfficeGraphCheckRunsPage($id: ID!, $cursor: String!) {
    node(id: $id) {
      ... on PullRequest {
        commits(last: 1) {
          nodes {
            commit {
              statusCheckRollup {
                contexts(first: 100, after: $cursor) {
                  nodes {
                    __typename
                    ... on CheckRun {
                      id
                      databaseId
                      checkSuite { databaseId }
                      name
                      status
                      conclusion
                      detailsUrl
                      startedAt
                      completedAt
                    }
                  }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
          }
        }
      }
    }
  }
  """

  @impl true
  def fetch(%{
        object_type: object_type,
        object_id: object_id,
        external_installation_id: installation_id,
        credential: credential
      })
      when object_type in ~w(pull_request review_comment check_run) and
             is_binary(object_id) and object_id != "" and is_integer(installation_id) and
             installation_id > 0 and is_binary(credential) do
    with {:ok, token} <- installation_token(installation_id, credential),
         {:ok, pull_request_id} <- resolve_pull_request(token, object_type, object_id),
         {:ok, response} <- graphql(token, @pull_request_query, %{"id" => pull_request_id}),
         {:ok, pull_request} <- response_node(response),
         {:ok, pull_request} <- complete_snapshot(token, pull_request),
         {:ok, snapshot} <- normalize_snapshot(pull_request) do
      {:ok, snapshot}
    end
  end

  def fetch(_request), do: {:error, :invalid_provider_response}

  @impl true
  def find_review_reply(request, credential) when is_map(request) and is_binary(credential) do
    with {:ok, token} <- outbound_token(request, credential),
         {:ok, context} <- outbound_context(token, request, :review_comment),
         {:ok, reply} <- find_reply(token, context, reply_marker(request)) do
      {:ok, reply}
    end
  end

  def find_review_reply(_request, _credential), do: {:error, :invalid_provider_response}

  @impl true
  def reply_to_review(request, credential) when is_map(request) and is_binary(credential) do
    with {:ok, token} <- outbound_token(request, credential),
         {:ok, context} <- outbound_context(token, request, :review_comment),
         {:ok, body} <- required_nonblank(request, :body),
         {:ok, marker} <- reply_marker(request),
         {:ok, response, _headers} <-
           rest(
             token,
             :post,
             review_reply_path(context),
             %{"body" => body <> "\n\n" <> marker}
           ),
         {:ok, identity} <- response_identity(response) do
      {:ok, identity}
    end
  end

  def reply_to_review(_request, _credential), do: {:error, :invalid_provider_response}

  @impl true
  def update_check(request, credential) when is_map(request) and is_binary(credential) do
    with {:ok, token} <- outbound_token(request, credential),
         {:ok, context} <- outbound_context(token, request, :check_run),
         {:ok, input} <- check_input(request),
         {:ok, response, _headers} <-
           rest(token, :patch, check_run_path(context), input),
         {:ok, identity} <- response_identity(response) do
      {:ok, identity}
    end
  end

  def update_check(_request, _credential), do: {:error, :invalid_provider_response}

  @doc false
  def clear_token_cache do
    __MODULE__.TokenCache.clear()
  end

  defp resolve_pull_request(token, object_type, object_id) do
    with {:ok, response} <- graphql(token, @resolve_query, %{"id" => object_id}),
         {:ok, node} <- response_node(response) do
      pull_request_id(node, object_type)
    end
  end

  defp pull_request_id(%{"id" => id}, "pull_request") when is_binary(id) and id != "",
    do: {:ok, id}

  defp pull_request_id(%{"pullRequest" => %{"id" => id}}, "review_comment")
       when is_binary(id) and id != "",
       do: {:ok, id}

  defp pull_request_id(
         %{"checkSuite" => %{"pullRequests" => %{"nodes" => [%{"id" => id} | _]}}},
         "check_run"
       )
       when is_binary(id) and id != "",
       do: {:ok, id}

  defp pull_request_id(_node, _object_type), do: {:error, :invalid_provider_response}

  defp normalize_snapshot(pull_request) do
    with {:ok, updated_at_raw} <- required_nonblank(pull_request, "updatedAt"),
         {:ok, updated_at} <- datetime(updated_at_raw),
         {:ok, repository} <- normalize_repository(pull_request["repository"]),
         {:ok, pull_request_snapshot} <- normalize_pull_request(pull_request),
         {:ok, threads, comments} <- normalize_threads(pull_request["reviewThreads"]),
         {:ok, checks} <- normalize_checks(pull_request["commits"]) do
      {:ok,
       %Adapter.ReconciliationSnapshot{
         provider_version: updated_at_raw,
         provider_sequence: DateTime.to_unix(updated_at, :microsecond),
         provider_updated_at: updated_at,
         repository: repository,
         pull_request: pull_request_snapshot,
         review_threads: threads,
         review_comments: comments,
         check_runs: checks
       }}
    end
  end

  defp normalize_repository(repository) when is_map(repository) do
    with {:ok, node_id} <- required_nonblank(repository, "id"),
         {:ok, name} <- required_nonblank(repository, "name"),
         {:ok, full_name} <- required_nonblank(repository, "nameWithOwner"),
         {:ok, owner_login} <- nested_nonblank(repository, ["owner", "login"]),
         {:ok, visibility} <- enum_value(repository, "visibility", ~w(public private internal)) do
      {:ok,
       %Adapter.RepositorySnapshot{
         node_id: node_id,
         database_id: optional_positive_integer(repository["databaseId"]),
         name: name,
         full_name: full_name,
         owner_login: owner_login,
         default_ref_name: get_in(repository, ["defaultBranchRef", "name"]),
         visibility: visibility,
         url: optional_string(repository["url"])
       }}
    end
  end

  defp normalize_repository(_repository), do: {:error, :invalid_provider_response}

  defp normalize_pull_request(pull_request) do
    with {:ok, node_id} <- required_nonblank(pull_request, "id"),
         {:ok, number} <- positive_integer(pull_request, "number"),
         {:ok, title} <- required_nonblank(pull_request, "title"),
         {:ok, state} <- enum_value(pull_request, "state", ~w(open closed merged)),
         {:ok, is_draft} <- boolean_value(pull_request, "isDraft"),
         {:ok, opened_at} <- optional_datetime(pull_request["createdAt"]),
         {:ok, closed_at} <- optional_datetime(pull_request["closedAt"]),
         {:ok, merged_at} <- optional_datetime(pull_request["mergedAt"]) do
      {:ok,
       %Adapter.PullRequestSnapshot{
         node_id: node_id,
         database_id: optional_positive_integer(pull_request["databaseId"]),
         number: number,
         title: title,
         body: optional_string(pull_request["body"]),
         state: state,
         is_draft: is_draft,
         author_label: get_in(pull_request, ["author", "login"]),
         url: optional_string(pull_request["url"]),
         opened_at: opened_at,
         closed_at: closed_at,
         merged_at: merged_at
       }}
    end
  end

  defp normalize_threads(%{"nodes" => nodes}) when is_list(nodes) do
    Enum.reduce_while(nodes, {:ok, [], []}, fn thread, {:ok, threads, comment_groups} ->
      with {:ok, normalized_thread} <- normalize_thread(thread),
           {:ok, normalized_comments} <- normalize_comments(thread, normalized_thread.node_id) do
        {:cont, {:ok, [normalized_thread | threads], [normalized_comments | comment_groups]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, threads, comment_groups} ->
        {:ok, Enum.reverse(threads), comment_groups |> Enum.reverse() |> List.flatten()}

      error ->
        error
    end
  end

  defp normalize_threads(_threads), do: {:error, :invalid_provider_response}

  defp normalize_thread(thread) when is_map(thread) do
    with {:ok, node_id} <- required_nonblank(thread, "id"),
         {:ok, resolved?} <- boolean_value(thread, "isResolved"),
         {:ok, outdated?} <- boolean_value(thread, "isOutdated") do
      state = if outdated?, do: "outdated", else: if(resolved?, do: "resolved", else: "open")

      {:ok,
       %Adapter.ReviewThreadSnapshot{
         node_id: node_id,
         state: state,
         path: optional_string(thread["path"]),
         line: optional_positive_integer(thread["line"]),
         side: optional_string(thread["diffSide"]),
         resolved_at: nil
       }}
    end
  end

  defp normalize_thread(_thread), do: {:error, :invalid_provider_response}

  defp normalize_comments(%{"comments" => %{"nodes" => nodes}}, thread_node_id)
       when is_list(nodes) do
    map_results(nodes, &normalize_comment(&1, thread_node_id))
  end

  defp normalize_comments(_thread, _thread_node_id),
    do: {:error, :invalid_provider_response}

  defp normalize_comment(comment, thread_node_id) when is_map(comment) do
    with {:ok, node_id} <- required_nonblank(comment, "id"),
         {:ok, body} <- string_value(comment, "body"),
         {:ok, state} <- normalize_comment_state(comment),
         {:ok, created_at} <- optional_datetime(comment["createdAt"]) do
      {:ok,
       %Adapter.ReviewCommentSnapshot{
         node_id: node_id,
         database_id: optional_positive_integer(comment["databaseId"]),
         review_database_id:
           optional_positive_integer(get_in(comment, ["pullRequestReview", "databaseId"])),
         review_thread_node_id: thread_node_id,
         parent_comment_node_id: get_in(comment, ["replyTo", "id"]),
         body: body,
         author_label: get_in(comment, ["author", "login"]),
         state: state,
         published_at: created_at,
         url: optional_string(comment["url"])
       }}
    end
  end

  defp normalize_comment(_comment, _thread_node_id),
    do: {:error, :invalid_provider_response}

  defp normalize_comment_state(%{"isMinimized" => true}), do: {:ok, "minimized"}

  defp normalize_comment_state(comment) do
    case downcase_string(comment["state"]) do
      "pending" -> {:ok, "pending"}
      "submitted" -> {:ok, "published"}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp normalize_checks(%{"nodes" => [%{"commit" => commit} | _]}) do
    nodes = get_in(commit, ["statusCheckRollup", "contexts", "nodes"]) || []

    nodes
    |> Enum.filter(&(&1["__typename"] in [nil, "CheckRun"]))
    |> map_results(&normalize_check/1)
  end

  defp normalize_checks(%{"nodes" => []}), do: {:ok, []}
  defp normalize_checks(_commits), do: {:error, :invalid_provider_response}

  defp normalize_check(check) when is_map(check) do
    with {:ok, node_id} <- required_nonblank(check, "id"),
         {:ok, name} <- required_nonblank(check, "name"),
         {:ok, provider_status} <-
           enum_value(
             check,
             "status",
             ~w(requested waiting pending queued in_progress completed)
           ),
         {:ok, started_at} <- optional_datetime(check["startedAt"]),
         {:ok, completed_at} <- optional_datetime(check["completedAt"]) do
      status =
        if provider_status in ~w(requested waiting pending), do: "queued", else: provider_status

      conclusion =
        if status == "completed", do: downcase_string(check["conclusion"]), else: nil

      {:ok,
       %Adapter.CheckRunSnapshot{
         node_id: node_id,
         database_id: optional_positive_integer(check["databaseId"]),
         check_suite_database_id:
           optional_positive_integer(get_in(check, ["checkSuite", "databaseId"])),
         name: name,
         status: status,
         conclusion: conclusion,
         details_url: optional_string(check["detailsUrl"]),
         started_at: started_at,
         completed_at: completed_at
       }}
    end
  end

  defp normalize_check(_check), do: {:error, :invalid_provider_response}

  defp complete_snapshot(token, %{"id" => pull_request_id} = pull_request) do
    with {:ok, thread_connection} <-
           complete_thread_pages(token, pull_request_id, pull_request["reviewThreads"], 1),
         {:ok, thread_nodes} <-
           complete_thread_comments(token, thread_connection["nodes"]),
         {:ok, check_connection} <-
           complete_check_pages(token, pull_request_id, check_connection(pull_request), 1) do
      pull_request =
        pull_request
        |> put_in(["reviewThreads"], %{thread_connection | "nodes" => thread_nodes})
        |> put_check_connection(check_connection)

      {:ok, pull_request}
    end
  end

  defp complete_snapshot(_token, _pull_request), do: {:error, :invalid_provider_response}

  defp complete_thread_pages(_token, _pull_request_id, connection, _page)
       when not is_map(connection),
       do: {:error, :invalid_provider_response}

  defp complete_thread_pages(_token, _pull_request_id, _connection, page)
       when page > @max_snapshot_pages,
       do: {:error, :invalid_provider_response}

  defp complete_thread_pages(token, pull_request_id, connection, page) do
    append_connection_page(
      connection,
      fn cursor ->
        with {:ok, response} <-
               graphql(token, @review_threads_page_query, %{
                 "id" => pull_request_id,
                 "cursor" => cursor
               }),
             {:ok, node} <- response_node(response) do
          connection_value(node, "reviewThreads")
        end
      end,
      &complete_thread_pages(token, pull_request_id, &1, page + 1)
    )
  end

  defp complete_thread_comments(token, threads) when is_list(threads) do
    map_results(threads, fn thread ->
      with {:ok, thread_id} <- required_nonblank(thread, "id"),
           {:ok, comments} <- complete_comment_pages(token, thread_id, thread["comments"], 1) do
        {:ok, Map.put(thread, "comments", comments)}
      end
    end)
  end

  defp complete_thread_comments(_token, _threads),
    do: {:error, :invalid_provider_response}

  defp complete_comment_pages(_token, _thread_id, connection, _page)
       when not is_map(connection),
       do: {:error, :invalid_provider_response}

  defp complete_comment_pages(_token, _thread_id, _connection, page)
       when page > @max_snapshot_pages,
       do: {:error, :invalid_provider_response}

  defp complete_comment_pages(token, thread_id, connection, page) do
    append_connection_page(
      connection,
      fn cursor ->
        with {:ok, response} <-
               graphql(token, @thread_comments_page_query, %{
                 "id" => thread_id,
                 "cursor" => cursor
               }),
             {:ok, node} <- response_node(response) do
          connection_value(node, "comments")
        end
      end,
      &complete_comment_pages(token, thread_id, &1, page + 1)
    )
  end

  defp complete_check_pages(_token, _pull_request_id, nil, _page), do: {:ok, nil}

  defp complete_check_pages(_token, _pull_request_id, connection, _page)
       when not is_map(connection),
       do: {:error, :invalid_provider_response}

  defp complete_check_pages(_token, _pull_request_id, _connection, page)
       when page > @max_snapshot_pages,
       do: {:error, :invalid_provider_response}

  defp complete_check_pages(token, pull_request_id, connection, page) do
    append_connection_page(
      connection,
      fn cursor ->
        with {:ok, response} <-
               graphql(token, @check_runs_page_query, %{
                 "id" => pull_request_id,
                 "cursor" => cursor
               }),
             {:ok, node} <- response_node(response) do
          node
          |> check_connection()
          |> case do
            nil -> {:error, :invalid_provider_response}
            value -> {:ok, value}
          end
        end
      end,
      &complete_check_pages(token, pull_request_id, &1, page + 1)
    )
  end

  defp append_connection_page(
         %{"nodes" => nodes, "pageInfo" => %{"hasNextPage" => false}} = connection,
         _fetch,
         _continue
       )
       when is_list(nodes),
       do: {:ok, connection}

  defp append_connection_page(
         %{
           "nodes" => nodes,
           "pageInfo" => %{"hasNextPage" => true, "endCursor" => cursor}
         },
         fetch,
         continue
       )
       when is_list(nodes) and is_binary(cursor) and cursor != "" do
    with {:ok, %{"nodes" => next_nodes} = next_connection} when is_list(next_nodes) <-
           fetch.(cursor) do
      continue.(%{next_connection | "nodes" => nodes ++ next_nodes})
    else
      {:ok, _invalid} -> {:error, :invalid_provider_response}
      {:error, _reason} = error -> error
    end
  end

  defp append_connection_page(_connection, _fetch, _continue),
    do: {:error, :invalid_provider_response}

  defp connection_value(node, key) do
    case node[key] do
      %{"nodes" => nodes, "pageInfo" => page_info} = connection
      when is_list(nodes) and is_map(page_info) ->
        {:ok, connection}

      _invalid ->
        {:error, :invalid_provider_response}
    end
  end

  defp check_connection(value) do
    get_in(value, [
      "commits",
      "nodes",
      Access.at(0),
      "commit",
      "statusCheckRollup",
      "contexts"
    ])
  end

  defp put_check_connection(pull_request, nil), do: pull_request

  defp put_check_connection(pull_request, connection) do
    put_in(
      pull_request,
      [
        "commits",
        "nodes",
        Access.at(0),
        "commit",
        "statusCheckRollup",
        "contexts"
      ],
      connection
    )
  end

  defp outbound_token(request, credential) do
    with {:ok, installation_id} <- positive_integer(request, :external_installation_id) do
      installation_token(installation_id, credential)
    end
  end

  defp outbound_context(token, request, kind) do
    with {:ok, target_node_id} <- required_nonblank(request, :target_node_id),
         {:ok, response} <- graphql(token, @outbound_context_query, %{"id" => target_node_id}),
         {:ok, node} <- response_node(response) do
      normalize_outbound_context(node, kind)
    end
  end

  defp normalize_outbound_context(node, :review_comment) do
    with {:ok, database_id} <- positive_integer(node, "databaseId"),
         {:ok, number} <- nested_positive_integer(node, ["pullRequest", "number"]),
         {:ok, repository} <-
           nested_nonblank(node, ["pullRequest", "repository", "nameWithOwner"]) do
      {:ok, %{database_id: database_id, number: number, repository: repository}}
    end
  end

  defp normalize_outbound_context(node, :check_run) do
    with {:ok, database_id} <- positive_integer(node, "databaseId"),
         {:ok, repository} <- nested_nonblank(node, ["checkSuite", "repository", "nameWithOwner"]) do
      {:ok, %{database_id: database_id, repository: repository}}
    end
  end

  defp find_reply(token, context, {:ok, marker}),
    do: find_reply_page(token, context, marker, 1)

  defp find_reply(_token, _context, {:error, reason}), do: {:error, reason}

  defp find_reply_page(_token, _context, _marker, page) when page > @max_comment_pages,
    do: {:error, :invalid_provider_response}

  defp find_reply_page(token, context, marker, page) do
    path =
      "/repos/#{repository_path(context.repository)}/pulls/#{context.number}/comments?per_page=100&page=#{page}"

    with {:ok, comments, _headers} when is_list(comments) <- rest(token, :get, path, nil) do
      case Enum.find(comments, &reply_marker?(&1, marker)) do
        nil when length(comments) == 100 -> find_reply_page(token, context, marker, page + 1)
        nil -> {:ok, nil}
        comment -> response_identity(comment)
      end
    else
      {:ok, _invalid, _headers} -> {:error, :invalid_provider_response}
      {:error, _reason} = error -> error
    end
  end

  defp reply_marker(request) do
    with {:ok, key} <- required_nonblank(request, :idempotency_key) do
      {:ok, "<!-- office-graph-action:#{key} -->"}
    end
  end

  defp reply_marker?(%{"body" => body}, marker) when is_binary(body),
    do: String.contains?(body, marker)

  defp reply_marker?(_comment, _marker), do: false

  defp review_reply_path(context) do
    "/repos/#{repository_path(context.repository)}/pulls/#{context.number}/comments/#{context.database_id}/replies"
  end

  defp check_run_path(context) do
    "/repos/#{repository_path(context.repository)}/check-runs/#{context.database_id}"
  end

  defp repository_path(repository) do
    repository
    |> String.split("/", parts: 2)
    |> Enum.map_join("/", &URI.encode/1)
  end

  defp check_input(request) do
    with {:ok, status} <- enum_value(request, :status, ~w(queued in_progress completed)),
         {:ok, details_url} <- required_nonblank(request, :details_url),
         {:ok, conclusion} <- check_conclusion(request, status) do
      {:ok,
       %{"status" => status, "conclusion" => conclusion, "details_url" => details_url}
       |> Enum.reject(fn {_key, value} -> is_nil(value) end)
       |> Map.new()}
    end
  end

  defp check_conclusion(request, "completed") do
    enum_value(
      request,
      :conclusion,
      ~w(success failure neutral cancelled skipped timed_out action_required)
    )
  end

  defp check_conclusion(request, _status) do
    if value(request, :conclusion) in [nil, ""],
      do: {:ok, nil},
      else: {:error, :invalid_provider_response}
  end

  defp response_identity(response) when is_map(response) do
    id = response["node_id"] || response["id"]
    version = response["updated_at"]

    cond do
      is_binary(id) and id != "" ->
        {:ok, %{id: id, version: optional_string(version)}}

      is_integer(id) and id > 0 ->
        {:ok, %{id: Integer.to_string(id), version: optional_string(version)}}

      true ->
        {:error, :invalid_provider_response}
    end
  end

  defp response_identity(_response), do: {:error, :invalid_provider_response}

  defp installation_token(installation_id, credential) do
    with {:ok, app_id} <- configured_app_id() do
      case cached_token(installation_id, app_id) do
        {:ok, token} -> {:ok, token}
        :miss -> create_installation_token(installation_id, app_id, credential)
      end
    end
  end

  defp create_installation_token(installation_id, app_id, credential) do
    with {:ok, jwt} <- app_jwt(app_id, credential),
         {:ok, response, _headers} <-
           request_json(
             :post,
             api_url() <> "/app/installations/#{installation_id}/access_tokens",
             app_headers(jwt),
             %{}
           ),
         {:ok, token} <- required_nonblank(response, "token"),
         {:ok, expires_at} <- datetime(response["expires_at"]) do
      cache_token(installation_id, app_id, token, expires_at)
      {:ok, token}
    end
  end

  defp app_jwt(app_id, credential) do
    now = System.system_time(:second)

    header = encode_segment(%{"alg" => "RS256", "typ" => "JWT"})
    payload = encode_segment(%{"iat" => now - 60, "exp" => now + 540, "iss" => app_id})
    signing_input = header <> "." <> payload

    with {:ok, private_key} <- decode_private_key(credential) do
      signature = :public_key.sign(signing_input, :sha256, private_key)
      {:ok, signing_input <> "." <> Base.url_encode64(signature, padding: false)}
    end
  rescue
    _error -> {:error, :invalid_credential}
  end

  defp decode_private_key(credential) do
    case :public_key.pem_decode(credential) do
      [entry | _] -> {:ok, :public_key.pem_entry_decode(entry)}
      _invalid -> {:error, :invalid_credential}
    end
  rescue
    _error -> {:error, :invalid_credential}
  end

  defp encode_segment(value) do
    value |> Jason.encode!() |> Base.url_encode64(padding: false)
  end

  defp graphql(token, query, variables) do
    with {:ok, response, _headers} <-
           request_json(
             :post,
             graphql_url(),
             installation_headers(token),
             %{"query" => query, "variables" => variables}
           ) do
      case response do
        %{"data" => _data, "errors" => errors} when is_list(errors) and errors != [] ->
          classify_graphql_errors(errors)

        %{"data" => data} when is_map(data) ->
          {:ok, data}

        _invalid ->
          {:error, :invalid_provider_response}
      end
    end
  end

  defp classify_graphql_errors(errors) do
    if Enum.any?(errors, &(get_in(&1, ["type"]) == "RATE_LIMITED")),
      do: {:error, {:rate_limited, DateTime.add(DateTime.utc_now(), 60, :second)}},
      else: {:error, :invalid_provider_response}
  end

  defp rest(token, method, path, body) do
    request_json(method, api_url() <> path, installation_headers(token), body)
  end

  defp request_json(method, url, headers, body) do
    encoded_body = if is_nil(body), do: nil, else: Jason.encode!(body)

    case http_client().request(method, url, headers, encoded_body) do
      {:ok, %{status: status, headers: response_headers, body: response_body}}
      when status in 200..299 and is_binary(response_body) ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, decoded, response_headers}
          {:error, _error} -> {:error, :invalid_provider_response}
        end

      {:ok, %{status: status, headers: response_headers}} ->
        {:error, classify_http_failure(status, response_headers)}

      {:error, :network_error} ->
        {:error, :network_error}

      {:error, _reason} ->
        {:error, :network_error}

      _invalid ->
        {:error, :invalid_provider_response}
    end
  end

  defp classify_http_failure(status, headers) when status in [403, 429] do
    if status == 429 or header(headers, "x-ratelimit-remaining") == "0" do
      reset_at =
        case Integer.parse(header(headers, "x-ratelimit-reset") || "") do
          {seconds, ""} ->
            case DateTime.from_unix(seconds) do
              {:ok, datetime} -> datetime
              {:error, _reason} -> DateTime.add(DateTime.utc_now(), 60, :second)
            end

          _invalid ->
            DateTime.add(DateTime.utc_now(), 60, :second)
        end

      {:rate_limited, reset_at}
    else
      :permission_denied
    end
  end

  defp classify_http_failure(401, _headers), do: :invalid_credential
  defp classify_http_failure(status, _headers) when status in 500..599, do: :provider_unavailable
  defp classify_http_failure(_status, _headers), do: :invalid_provider_response

  defp app_headers(jwt) do
    common_headers() |> Map.put("authorization", "Bearer " <> jwt)
  end

  defp installation_headers(token) do
    common_headers() |> Map.put("authorization", "Bearer " <> token)
  end

  defp common_headers do
    %{
      "accept" => "application/vnd.github+json",
      "content-type" => "application/json",
      "user-agent" => "OfficeGraph/0.1",
      "x-github-api-version" => "2022-11-28"
    }
  end

  defp configured_app_id do
    case Application.get_env(:office_graph, :github_app_id) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {integer, ""} when integer > 0 -> {:ok, integer}
          _invalid -> {:error, :adapter_unavailable}
        end

      _missing ->
        {:error, :adapter_unavailable}
    end
  end

  defp api_url do
    :office_graph
    |> Application.get_env(:github_api_url, "https://api.github.com")
    |> String.trim_trailing("/")
  end

  defp graphql_url do
    Application.get_env(:office_graph, :github_graphql_url, api_url() <> "/graphql")
  end

  defp http_client do
    Application.get_env(
      :office_graph,
      :github_http_client,
      OfficeGraph.GitHubIntegration.Adapter.GitHub.HTTPClient.Httpc
    )
  end

  defp cached_token(installation_id, app_id) do
    __MODULE__.TokenCache.fetch(installation_id, app_id)
  end

  defp cache_token(installation_id, app_id, token, expires_at) do
    __MODULE__.TokenCache.put(installation_id, app_id, token, expires_at)
  end

  defp response_node(%{"node" => node}) when is_map(node), do: {:ok, node}
  defp response_node(_response), do: {:error, :invalid_provider_response}

  defp required_nonblank(map, key) do
    case value(map, key) do
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp string_value(map, key) do
    case value(map, key) do
      value when is_binary(value) -> {:ok, value}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp positive_integer(map, key) do
    case value(map, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp nested_nonblank(map, path), do: required_nonblank(%{value: get_in(map, path)}, :value)

  defp nested_positive_integer(map, path),
    do: positive_integer(%{value: get_in(map, path)}, :value)

  defp boolean_value(map, key) do
    case value(map, key) do
      value when is_boolean(value) -> {:ok, value}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp enum_value(map, key, allowed) do
    normalized = map |> value(key) |> downcase_string()
    if normalized in allowed, do: {:ok, normalized}, else: {:error, :invalid_provider_response}
  end

  defp datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp datetime(_value), do: {:error, :invalid_provider_response}

  defp optional_datetime(nil), do: {:ok, nil}
  defp optional_datetime(value), do: datetime(value)

  defp optional_positive_integer(value) when is_integer(value) and value > 0, do: value
  defp optional_positive_integer(_value), do: nil

  defp optional_string(value) when is_binary(value), do: value
  defp optional_string(_value), do: nil

  defp downcase_string(value) when is_binary(value), do: String.downcase(value)
  defp downcase_string(_value), do: nil

  defp value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp value(map, key) when is_map(map), do: Map.get(map, key)

  defp header(headers, name) when is_map(headers) do
    Map.get(headers, name) || Map.get(headers, String.downcase(name))
  end

  defp header(_headers, _name), do: nil

  defp map_results(items, mapper) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, results} ->
      case mapper.(item) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end
end
