defmodule OfficeGraph.SoftwareProving.ResourceTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Operations}
  alias OfficeGraph.ExternalRefs.ExternalReference
  alias OfficeGraph.Integrations.ExternalSource

  alias OfficeGraph.SoftwareProving.{
    CheckRun,
    Commit,
    PullRequest,
    Repository,
    RepositoryRef,
    ReviewComment,
    ReviewThread
  }

  alias OfficeGraph.SoftwareProving.GitHub.{
    CheckRunExtension,
    PullRequestExtension,
    RepositoryExtension,
    ReviewCommentExtension,
    ReviewThreadExtension
  }

  setup do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :integration_reconcile)

    source =
      Ash.create!(
        ExternalSource,
        %{
          key: "github:#{Ecto.UUID.generate()}",
          name: "GitHub",
          kind: "source_code"
        },
        action: :create,
        authorize?: false
      )

    %{bootstrap: bootstrap, operation: operation, source: source}
  end

  test "stores a complete review graph in provider-neutral resources", context do
    repository =
      create!(Repository, base_attrs(context, 10), %{
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        default_ref_name: "refs/heads/main",
        visibility: "private"
      })

    commit =
      create!(Commit, base_attrs(context, 11), %{
        repository_id: repository.id,
        oid: String.duplicate("a", 40),
        summary: "Add typed integration resources",
        authored_at: DateTime.utc_now(),
        committed_at: DateTime.utc_now()
      })

    base_ref =
      create!(RepositoryRef, base_attrs(context, 12), %{
        repository_id: repository.id,
        name: "refs/heads/main",
        ref_type: "branch",
        target_commit_id: commit.id,
        is_default: true
      })

    head_ref =
      create!(RepositoryRef, base_attrs(context, 13), %{
        repository_id: repository.id,
        name: "refs/heads/codex/github-review-integration",
        ref_type: "branch",
        target_commit_id: commit.id,
        is_default: false
      })

    pull_request =
      create!(PullRequest, base_attrs(context, 14), %{
        repository_id: repository.id,
        number: 25,
        title: "Add GitHub review integration",
        body: "Provider-neutral review intake",
        state: "open",
        is_draft: false,
        base_ref_id: base_ref.id,
        head_ref_id: head_ref.id,
        author_label: "un3qual",
        opened_at: DateTime.utc_now()
      })

    thread =
      create!(ReviewThread, base_attrs(context, 15), %{
        pull_request_id: pull_request.id,
        state: "open",
        path: "lib/office_graph/software_proving.ex",
        line: 12,
        side: "right"
      })

    comment =
      create!(ReviewComment, base_attrs(context, 16), %{
        pull_request_id: pull_request.id,
        review_thread_id: thread.id,
        body: "Keep provider identity outside the shared resource.",
        author_label: "review-bot",
        state: "published",
        published_at: DateTime.utc_now()
      })

    check =
      create!(CheckRun, base_attrs(context, 17), %{
        repository_id: repository.id,
        commit_id: commit.id,
        pull_request_id: pull_request.id,
        name: "verify",
        status: "completed",
        conclusion: "success",
        details_url: "https://github.example/checks/17",
        started_at: DateTime.utc_now(),
        completed_at: DateTime.utc_now()
      })

    assert repository.organization_id == context.bootstrap.organization.id
    assert repository.workspace_id == context.bootstrap.workspace.id
    assert repository.source_id == context.source.id
    assert repository.provider_sequence == 10
    assert repository.sync_state == "synced"
    assert repository.lifecycle_state == "active"
    assert commit.repository_id == repository.id
    assert base_ref.target_commit_id == commit.id
    assert pull_request.base_ref_id == base_ref.id
    assert pull_request.head_ref_id == head_ref.id
    assert comment.review_thread_id == thread.id
    assert check.pull_request_id == pull_request.id
  end

  test "keeps GitHub-only identity in extension resources and external references", context do
    repository =
      create!(Repository, base_attrs(context, 20), %{
        name: "office-graph-backend",
        full_name: "Un3qual/office-graph-backend",
        default_ref_name: "refs/heads/main",
        visibility: "private"
      })

    pull_request =
      create!(PullRequest, base_attrs(context, 21), %{
        repository_id: repository.id,
        number: 25,
        title: "Add GitHub review integration",
        state: "open",
        is_draft: false,
        author_label: "un3qual",
        opened_at: DateTime.utc_now()
      })

    thread =
      create!(ReviewThread, base_attrs(context, 22), %{
        pull_request_id: pull_request.id,
        state: "open",
        path: "lib/office_graph/software_proving.ex",
        line: 12,
        side: "right"
      })

    comment =
      create!(ReviewComment, base_attrs(context, 23), %{
        pull_request_id: pull_request.id,
        review_thread_id: thread.id,
        body: "Provider-only data belongs in an extension.",
        author_label: "review-bot",
        state: "published",
        published_at: DateTime.utc_now()
      })

    check =
      create!(CheckRun, base_attrs(context, 24), %{
        repository_id: repository.id,
        name: "verify",
        status: "queued"
      })

    assert {:ok, _extension} =
             Ash.create(
               RepositoryExtension,
               %{
                 repository_id: repository.id,
                 node_id: "R_kgDOOfficeGraph",
                 database_id: 10_001,
                 owner_login: "Un3qual"
               },
               action: :create,
               authorize?: false
             )

    assert {:ok, _extension} =
             Ash.create(
               PullRequestExtension,
               %{pull_request_id: pull_request.id, node_id: "PR_25", database_id: 25},
               action: :create,
               authorize?: false
             )

    assert {:ok, _extension} =
             Ash.create(
               ReviewThreadExtension,
               %{review_thread_id: thread.id, node_id: "PRRT_1"},
               action: :create,
               authorize?: false
             )

    assert {:ok, _extension} =
             Ash.create(
               ReviewCommentExtension,
               %{
                 review_comment_id: comment.id,
                 node_id: "PRRC_1",
                 database_id: 101,
                 review_database_id: 100
               },
               action: :create,
               authorize?: false
             )

    assert {:ok, _extension} =
             Ash.create(
               CheckRunExtension,
               %{
                 check_run_id: check.id,
                 node_id: "CR_1",
                 database_id: 201,
                 check_suite_database_id: 200
               },
               action: :create,
               authorize?: false
             )

    assert {:ok, reference} =
             Ash.create(
               ExternalReference,
               %{
                 organization_id: context.bootstrap.organization.id,
                 source_id: context.source.id,
                 provider: "github",
                 object_type: "pull_request",
                 external_id: "25",
                 url: "https://github.com/Un3qual/office-graph-backend/pull/25",
                 sync_state: "synced",
                 operation_id: context.operation.id,
                 resource_type: "pull_request",
                 resource_id: pull_request.id
               },
               action: :create,
               authorize?: false
             )

    assert reference.organization_id == context.bootstrap.organization.id
    assert reference.provider == "github"
    assert reference.object_type == "pull_request"
    assert is_nil(Ash.Resource.Info.attribute(Repository, :github_node_id))
    assert Ash.Resource.Info.attribute(RepositoryExtension, :node_id)
  end

  test "supports native records without fabricated provider state and rejects invalid lifecycle",
       context do
    native_attrs = %{
      id: Ecto.UUID.generate(),
      organization_id: context.bootstrap.organization.id,
      workspace_id: context.bootstrap.workspace.id,
      source_id: nil,
      provider_version: nil,
      provider_sequence: nil,
      sync_state: "native",
      lifecycle_state: "active",
      operation_id: context.operation.id,
      name: "native-review-space",
      full_name: "native-review-space",
      default_ref_name: "refs/heads/main",
      visibility: "internal"
    }

    assert {:ok, repository} =
             Ash.create(Repository, native_attrs, action: :create, authorize?: false)

    assert is_nil(repository.source_id)
    assert repository.sync_state == "native"

    assert {:error, error} =
             Ash.create(
               Repository,
               %{native_attrs | id: Ecto.UUID.generate(), lifecycle_state: "mystery"},
               action: :create,
               authorize?: false
             )

    assert Exception.message(error) =~ "lifecycle_state"
  end

  defp base_attrs(context, provider_sequence) do
    %{
      id: Ecto.UUID.generate(),
      organization_id: context.bootstrap.organization.id,
      workspace_id: context.bootstrap.workspace.id,
      source_id: context.source.id,
      provider_version: "v#{provider_sequence}",
      provider_sequence: provider_sequence,
      provider_updated_at: DateTime.utc_now(),
      sync_state: "synced",
      lifecycle_state: "active",
      operation_id: context.operation.id
    }
  end

  defp create!(resource, common, specific) do
    Ash.create!(resource, Map.merge(common, specific), action: :create, authorize?: false)
  end
end
