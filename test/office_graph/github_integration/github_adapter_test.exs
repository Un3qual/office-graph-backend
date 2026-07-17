defmodule OfficeGraph.GitHubIntegration.GitHubAdapterTest do
  use ExUnit.Case, async: false

  alias OfficeGraph.GitHubIntegration.Adapter
  alias OfficeGraph.GitHubIntegration.Adapter.GitHub

  defmodule HTTPClient do
    @behaviour OfficeGraph.GitHubIntegration.Adapter.GitHub.HTTPClient

    def put(responses) do
      Process.put({__MODULE__, :responses}, responses)
      Process.put({__MODULE__, :requests}, [])
    end

    def requests do
      Process.get({__MODULE__, :requests}, []) |> Enum.reverse()
    end

    @impl true
    def request(method, url, headers, body) do
      requests = Process.get({__MODULE__, :requests}, [])
      Process.put({__MODULE__, :requests}, [{method, url, headers, body} | requests])

      case Process.get({__MODULE__, :responses}, []) do
        [response | remaining] ->
          Process.put({__MODULE__, :responses}, remaining)
          response

        [] ->
          {:error, :unexpected_http_request}
      end
    end
  end

  setup_all do
    private_key = :public_key.generate_key({:rsa, 2_048, 65_537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    {:ok, private_key: :public_key.pem_encode([pem_entry])}
  end

  setup do
    configured = %{
      app_id: Application.get_env(:office_graph, :github_app_id),
      api_url: Application.get_env(:office_graph, :github_api_url),
      client: Application.get_env(:office_graph, :github_http_client)
    }

    Application.put_env(:office_graph, :github_app_id, "12345")
    Application.put_env(:office_graph, :github_api_url, "https://api.github.test")
    Application.put_env(:office_graph, :github_http_client, HTTPClient)
    GitHub.clear_token_cache()

    on_exit(fn ->
      restore_env(:github_app_id, configured.app_id)
      restore_env(:github_api_url, configured.api_url)
      restore_env(:github_http_client, configured.client)
      GitHub.clear_token_cache()
    end)

    :ok
  end

  test "non-test configuration selects the live GitHub adapter" do
    config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)

    assert config[:office_graph][:github_adapter] == GitHub
  end

  test "missing App identity fails as configuration before provider access", context do
    Application.delete_env(:office_graph, :github_app_id)
    HTTPClient.put([])

    assert {:error, :adapter_unavailable} =
             GitHub.fetch(%{
               object_type: "pull_request",
               object_id: "PR_live",
               external_installation_id: 42,
               credential: context.private_key
             })

    assert HTTPClient.requests() == []
  end

  test "installation token not-found responses classify the binding as revoked", context do
    HTTPClient.put([
      error_response(404, %{"message" => "Not Found"})
    ])

    assert {:error, :installation_revoked} =
             GitHub.fetch(%{
               object_type: "pull_request",
               object_id: "PR_revoked",
               external_installation_id: 42,
               credential: context.private_key
             })

    assert length(HTTPClient.requests()) == 1
  end

  test "GraphQL forbidden errors preserve the permission-denied classification", context do
    HTTPClient.put([
      installation_token_response(),
      json_response(%{
        "data" => %{"node" => nil},
        "errors" => [%{"type" => "FORBIDDEN", "message" => "Resource not accessible"}]
      })
    ])

    assert {:error, :permission_denied} =
             GitHub.fetch(%{
               object_type: "pull_request",
               object_id: "PR_forbidden",
               external_installation_id: 42,
               credential: context.private_key
             })
  end

  test "secondary rate-limit responses remain retryable when primary quota remains", context do
    HTTPClient.put([
      installation_token_response(),
      error_response(
        403,
        %{"message" => "You have exceeded a secondary rate limit."},
        %{"retry-after" => "30", "x-ratelimit-remaining" => "4999"}
      )
    ])

    before = DateTime.utc_now()

    assert {:error, {:rate_limited, reset_at}} =
             GitHub.fetch(%{
               object_type: "pull_request",
               object_id: "PR_secondary_rate_limit",
               external_installation_id: 42,
               credential: context.private_key
             })

    assert DateTime.diff(reset_at, before, :second) in 29..31
  end

  test "fetch authenticates as the app and normalizes authoritative pull request state",
       context do
    HTTPClient.put([
      installation_token_response(),
      json_response(%{"data" => %{"node" => %{"id" => "PR_live"}}}),
      json_response(snapshot_response())
    ])

    assert {:ok, %Adapter.ReconciliationSnapshot{} = snapshot} =
             GitHub.fetch(%{
               object_type: "pull_request",
               object_id: "PR_live",
               external_installation_id: 42,
               credential: context.private_key
             })

    assert snapshot.provider_version == "2026-07-16T12:00:00Z"
    assert snapshot.repository.full_name == "Un3qual/office-graph-backend"
    assert snapshot.pull_request.node_id == "PR_live"
    assert [%{node_id: "PRRT_live", state: "open"}] = snapshot.review_threads

    assert [%{node_id: "PRRC_live", review_thread_node_id: "PRRT_live"}] =
             snapshot.review_comments

    assert [%{node_id: "CR_live", status: "completed", conclusion: "failure"}] =
             snapshot.check_runs

    [token_request, resolve_request, snapshot_request] = HTTPClient.requests()

    assert {:post, "https://api.github.test/app/installations/42/access_tokens", headers, "{}"} =
             token_request

    assert "Bearer " <> jwt = Map.fetch!(headers, "authorization")
    assert length(String.split(jwt, ".")) == 3

    for {_method, "https://api.github.test/graphql", request_headers, _body} <-
          [resolve_request, snapshot_request] do
      assert request_headers["authorization"] == "Bearer installation-token"
    end
  end

  test "check-run fetches use the webhook-selected pull request instead of an arbitrary first association",
       context do
    second_pull_request =
      snapshot_response()
      |> put_in(["data", "node", "id"], "PR_live_second")
      |> put_in(["data", "node", "databaseId"], 25)
      |> put_in(["data", "node", "number"], 25)

    HTTPClient.put([
      installation_token_response(),
      json_response(second_pull_request)
    ])

    assert {:ok, snapshot} =
             GitHub.fetch(%{
               object_type: "check_run",
               object_id: "CR_live",
               pull_request_id: "PR_live_second",
               external_installation_id: 42,
               credential: context.private_key
             })

    assert snapshot.pull_request.node_id == "PR_live_second"

    [_token_request, snapshot_request] = HTTPClient.requests()
    {_method, _url, _headers, encoded_body} = snapshot_request
    assert Jason.decode!(encoded_body)["variables"] == %{"id" => "PR_live_second"}
  end

  test "fetch follows authoritative review-thread pages instead of truncating the snapshot",
       context do
    first_page =
      put_in(
        snapshot_response(),
        ["data", "node", "reviewThreads", "pageInfo"],
        %{"hasNextPage" => true, "endCursor" => "thread-cursor-1"}
      )

    second_page = %{
      "data" => %{
        "node" => %{
          "reviewThreads" => %{
            "nodes" => [
              %{
                "id" => "PRRT_live_2",
                "isResolved" => true,
                "isOutdated" => false,
                "path" => "lib/second.ex",
                "line" => 9,
                "diffSide" => "RIGHT",
                "comments" => %{
                  "nodes" => [],
                  "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                }
              }
            ],
            "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
          }
        }
      }
    }

    HTTPClient.put([
      installation_token_response(),
      json_response(%{"data" => %{"node" => %{"id" => "PR_live"}}}),
      json_response(first_page),
      json_response(second_page)
    ])

    assert {:ok, snapshot} =
             GitHub.fetch(%{
               object_type: "pull_request",
               object_id: "PR_live",
               external_installation_id: 42,
               credential: context.private_key
             })

    assert Enum.map(snapshot.review_threads, & &1.node_id) == ["PRRT_live", "PRRT_live_2"]
  end

  test "fetch follows nested comment and check-run pages", context do
    first_page =
      snapshot_response()
      |> put_in(
        [
          "data",
          "node",
          "reviewThreads",
          "nodes",
          Access.at(0),
          "comments",
          "pageInfo"
        ],
        %{"hasNextPage" => true, "endCursor" => "comment-cursor-1"}
      )
      |> put_in(
        [
          "data",
          "node",
          "commits",
          "nodes",
          Access.at(0),
          "commit",
          "statusCheckRollup",
          "contexts",
          "pageInfo"
        ],
        %{"hasNextPage" => true, "endCursor" => "check-cursor-1"}
      )

    comment_page = %{
      "data" => %{
        "node" => %{
          "comments" => %{
            "nodes" => [
              %{
                "id" => "PRRC_live_reply",
                "databaseId" => 904,
                "body" => "Follow-up",
                "state" => "SUBMITTED",
                "isMinimized" => false,
                "createdAt" => "2026-07-16T11:32:00Z",
                "updatedAt" => "2026-07-16T11:33:00Z",
                "url" => "https://github.com/comment/904",
                "author" => %{"login" => "reviewer"},
                "replyTo" => %{"id" => "PRRC_live"},
                "pullRequestReview" => %{"databaseId" => 89}
              }
            ],
            "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
          }
        }
      }
    }

    check_page = %{
      "data" => %{
        "node" => %{
          "commits" => %{
            "nodes" => [
              %{
                "commit" => %{
                  "statusCheckRollup" => %{
                    "contexts" => %{
                      "nodes" => [
                        %{
                          "__typename" => "CheckRun",
                          "id" => "CR_live_2",
                          "databaseId" => 905,
                          "checkSuite" => %{"databaseId" => 78},
                          "name" => "frontend verify",
                          "status" => "COMPLETED",
                          "conclusion" => "SUCCESS",
                          "detailsUrl" => "https://github.com/check/905",
                          "startedAt" => "2026-07-16T11:51:00Z",
                          "completedAt" => "2026-07-16T11:59:00Z"
                        }
                      ],
                      "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                    }
                  }
                }
              }
            ]
          }
        }
      }
    }

    HTTPClient.put([
      installation_token_response(),
      json_response(%{"data" => %{"node" => %{"id" => "PR_live"}}}),
      json_response(first_page),
      json_response(comment_page),
      json_response(check_page)
    ])

    assert {:ok, snapshot} =
             GitHub.fetch(%{
               object_type: "pull_request",
               object_id: "PR_live",
               external_installation_id: 42,
               credential: context.private_key
             })

    assert Enum.map(snapshot.review_comments, & &1.node_id) == [
             "PRRC_live",
             "PRRC_live_reply"
           ]

    assert Enum.map(snapshot.check_runs, & &1.node_id) == ["CR_live", "CR_live_2"]
  end

  test "review reply callbacks reconcile the durable marker before creating a reply", context do
    marker = "<!-- office-graph-action:action-42 -->"

    HTTPClient.put([
      installation_token_response(),
      json_response(review_comment_context()),
      json_response([
        %{
          "id" => 901,
          "node_id" => "PRRC_existing_reply",
          "body" => "Already sent\n\n#{marker}",
          "updated_at" => "2026-07-16T12:30:00Z"
        }
      ])
    ])

    request = %{
      target_node_id: "PRRC_live",
      idempotency_key: "action-42",
      external_installation_id: 42,
      body: "Please address this.",
      expected_provider_version: "2026-07-16T12:00:00Z"
    }

    assert {:ok, %{id: "PRRC_existing_reply", version: "2026-07-16T12:30:00Z"}} =
             GitHub.find_review_reply(request, context.private_key)

    assert length(HTTPClient.requests()) == 3

    GitHub.clear_token_cache()

    HTTPClient.put([
      installation_token_response(),
      json_response(review_comment_context()),
      json_response(%{
        "id" => 902,
        "node_id" => "PRRC_created_reply",
        "updated_at" => "2026-07-16T12:31:00Z"
      })
    ])

    assert {:ok, %{id: "PRRC_created_reply", version: "2026-07-16T12:31:00Z"}} =
             GitHub.reply_to_review(request, context.private_key)

    {_method, _url, _headers, encoded_body} = List.last(HTTPClient.requests())

    assert Jason.decode!(encoded_body) == %{
             "body" => "Please address this.\n\n#{marker}"
           }
  end

  test "check updates resolve the repository and patch the selected check run", context do
    HTTPClient.put([
      installation_token_response(),
      json_response(check_run_context()),
      json_response(%{
        "id" => 903,
        "node_id" => "CR_live",
        "updated_at" => "2026-07-16T12:32:00Z"
      })
    ])

    assert {:ok, %{id: "CR_live", version: "2026-07-16T12:32:00Z"}} =
             GitHub.update_check(
               %{
                 target_node_id: "CR_live",
                 external_installation_id: 42,
                 status: "completed",
                 conclusion: "success",
                 details_url: "https://office-graph.test/checks/903"
               },
               context.private_key
             )

    assert {:patch, "https://api.github.test/repos/Un3qual/office-graph-backend/check-runs/903",
            _headers, encoded_body} = List.last(HTTPClient.requests())

    assert Jason.decode!(encoded_body) == %{
             "status" => "completed",
             "conclusion" => "success",
             "details_url" => "https://office-graph.test/checks/903"
           }
  end

  defp installation_token_response do
    expires_at = DateTime.utc_now() |> DateTime.add(3_600) |> DateTime.to_iso8601()

    json_response(
      %{
        "token" => "installation-token",
        "expires_at" => expires_at
      },
      201
    )
  end

  defp review_comment_context do
    %{
      "data" => %{
        "node" => %{
          "databaseId" => 901,
          "pullRequest" => %{
            "number" => 24,
            "repository" => %{"nameWithOwner" => "Un3qual/office-graph-backend"}
          }
        }
      }
    }
  end

  defp check_run_context do
    %{
      "data" => %{
        "node" => %{
          "databaseId" => 903,
          "checkSuite" => %{
            "repository" => %{"nameWithOwner" => "Un3qual/office-graph-backend"}
          }
        }
      }
    }
  end

  defp snapshot_response do
    %{
      "data" => %{
        "node" => %{
          "id" => "PR_live",
          "databaseId" => 24,
          "number" => 24,
          "title" => "Live GitHub adapter",
          "body" => "Normalize authoritative state.",
          "state" => "OPEN",
          "isDraft" => false,
          "updatedAt" => "2026-07-16T12:00:00Z",
          "createdAt" => "2026-07-16T11:00:00Z",
          "closedAt" => nil,
          "mergedAt" => nil,
          "url" => "https://github.com/Un3qual/office-graph-backend/pull/24",
          "author" => %{"login" => "reviewer"},
          "repository" => %{
            "id" => "R_live",
            "databaseId" => 101,
            "name" => "office-graph-backend",
            "nameWithOwner" => "Un3qual/office-graph-backend",
            "visibility" => "PRIVATE",
            "url" => "https://github.com/Un3qual/office-graph-backend",
            "owner" => %{"login" => "Un3qual"},
            "defaultBranchRef" => %{"name" => "main"}
          },
          "reviewThreads" => %{
            "nodes" => [
              %{
                "id" => "PRRT_live",
                "isResolved" => false,
                "isOutdated" => false,
                "path" => "lib/example.ex",
                "line" => 42,
                "diffSide" => "RIGHT",
                "comments" => %{
                  "nodes" => [
                    %{
                      "id" => "PRRC_live",
                      "databaseId" => 901,
                      "body" => "Fix the root cause.",
                      "state" => "SUBMITTED",
                      "createdAt" => "2026-07-16T11:30:00Z",
                      "updatedAt" => "2026-07-16T11:31:00Z",
                      "url" => "https://github.com/comment/901",
                      "author" => %{"login" => "review-bot"},
                      "replyTo" => nil,
                      "pullRequestReview" => %{"databaseId" => 88}
                    }
                  ],
                  "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                }
              }
            ],
            "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
          },
          "commits" => %{
            "nodes" => [
              %{
                "commit" => %{
                  "statusCheckRollup" => %{
                    "contexts" => %{
                      "nodes" => [
                        %{
                          "id" => "CR_live",
                          "databaseId" => 903,
                          "checkSuite" => %{"databaseId" => 77},
                          "name" => "mix verify",
                          "status" => "COMPLETED",
                          "conclusion" => "FAILURE",
                          "detailsUrl" => "https://github.com/check/903",
                          "startedAt" => "2026-07-16T11:40:00Z",
                          "completedAt" => "2026-07-16T11:50:00Z"
                        }
                      ],
                      "pageInfo" => %{"hasNextPage" => false, "endCursor" => nil}
                    }
                  }
                }
              }
            ]
          }
        }
      }
    }
  end

  defp json_response(body, status \\ 200) do
    {:ok, %{status: status, headers: %{}, body: Jason.encode!(body)}}
  end

  defp error_response(status, body, headers \\ %{}) do
    {:ok, %{status: status, headers: headers, body: Jason.encode!(body)}}
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)
end
