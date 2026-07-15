# GitHub Review Lifecycle And Permission Health Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close review-derived work when its parent thread is no longer actionable, reject replies to non-published comments, and report GitHub installation permission health against the capabilities the integration actually exposes.

**Architecture:** Reconciliation will derive comment actionability from both the reconciled comment state and its parent thread state in the same authoritative provider snapshot, avoiding per-comment reads. The outbound command boundary will enforce reply eligibility before action persistence, and health will reuse an explicit required-write-permission set rather than treating any permission entry as sufficient.

**Tech Stack:** Elixir 1.20, Erlang/OTP 29, Ash, Ecto/Postgres, ExUnit, OpenSpec 1.4.1, project Nix flake.

## Global Constraints

- Use the project Nix flake for every project runtime and CLI command.
- OpenSpec is the workflow source of truth; update canonical and archived GitHub integration specifications together.
- Preserve tenant scoping, replay safety, provider-version guards, and query-bounded projection assembly.
- Add behavior regressions before production changes and observe each regression fail for the reported reason.
- Keep the patch limited to the three current PR review findings.

---

### Task 1: Make Review Thread State Part Of Signal Actionability

**Files:**
- Modify: `test/office_graph/github_integration/product_mapping_test.exs`
- Modify: `lib/office_graph/github_integration/reconciler.ex`
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md`

**Interfaces:**
- Consumes: `Adapter.ReconciliationSnapshot.review_threads`, `Adapter.ReviewCommentSnapshot.review_thread_node_id`, and `WorkGraph.sync_integration_signal/4`.
- Produces: `review_comment_actionable?/2`, which returns true only for a published comment whose optional parent thread is open.

- [x] **Step 1: Write the failing lifecycle regression**

Add this product-mapping regression:

```elixir
test "resolved review threads do not create or retain open signals" do
  context = context("resolved-thread-signal-lifecycle")

  request =
    ReconciliationRequest.new!(%{
      installation_id: context.installation.id,
      object_type: "pull_request",
      object_id: "PR_mapping_44",
      delivery_id: "delivery-resolved-thread-signal-lifecycle"
    })

  open = %{mapping_snapshot() | check_runs: []}
  Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, open}})

  assert {:ok, open_outcome} =
           Reconciler.reconcile(operation!(context, request, "open-thread"), request)

  assert [signal_id] = open_outcome.signal_ids
  [thread] = open.review_threads

  resolved = %{
    open
    | provider_version: "v4",
      provider_sequence: 4,
      provider_updated_at: ~U[2026-07-14 13:01:00Z],
      review_threads: [
        %{thread | state: "resolved", resolved_at: ~U[2026-07-14 13:01:00Z]}
      ]
  }

  Provider.put(%{{"pull_request", "PR_mapping_44"} => {:ok, resolved}})

  assert {:ok, resolved_outcome} =
           Reconciler.reconcile(operation!(context, request, "resolved-thread"), request)

  assert resolved_outcome.signal_ids == []
  assert Ash.get!(Signal, signal_id, authorize?: false).state == "closed"

  first_seen_context = context("first-seen-resolved-thread")

  first_seen_request =
    ReconciliationRequest.new!(%{
      installation_id: first_seen_context.installation.id,
      object_type: "pull_request",
      object_id: "PR_mapping_44",
      delivery_id: "delivery-first-seen-resolved-thread"
    })

  signal_count = Repo.aggregate(Signal, :count)

  assert {:ok, first_seen_outcome} =
           Reconciler.reconcile(
             operation!(first_seen_context, first_seen_request, "first-seen-resolved"),
             first_seen_request
           )

  assert first_seen_outcome.signal_ids == []
  assert Repo.aggregate(Signal, :count) == signal_count
end
```

- [x] **Step 2: Run the regression to verify RED**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/github_integration/product_mapping_test.exs'`

Expected: FAIL because the published comment still leaves or creates an open signal when its thread is resolved.

- [x] **Step 3: Implement parent-thread-aware actionability**

Pass the authoritative review-thread snapshots into product mapping and use this implementation:

```elixir
signal_ids =
  map_product_work!(operation, comments, checks, snapshot.review_threads)

defp map_product_work!(operation, comments, checks, review_threads) do
  if is_nil(operation.workspace_id),
    do: [],
    else: map_workspace_product_work!(operation, comments, checks, review_threads)
end

defp map_workspace_product_work!(operation, comments, checks, review_threads) do
  thread_states = Map.new(review_threads, &{&1.node_id, &1.state})

  comment_signals =
    Enum.flat_map(comments, fn item ->
      actionable? = review_comment_actionable?(item, thread_states)

      result =
        WorkGraph.sync_integration_signal(
          operation,
          item.reference,
          %{
            title: "Review comment from #{item.record.author_label || "GitHub"}",
            body: item.record.body
          },
          actionable?
        )
        |> unwrap!()

      if actionable?, do: [result.signal.id], else: []
    end)

  check_signals =
    Enum.flat_map(checks, fn item ->
      actionable? = failing_check?(item.record)

      result =
        WorkGraph.sync_integration_signal(
          operation,
          item.reference,
          %{
            title: "Failing check: #{item.record.name}",
            body: "#{item.record.name} concluded with #{item.record.conclusion}."
          },
          actionable?
        )
        |> unwrap!()

      if actionable?, do: [result.signal.id], else: []
    end)

  comment_signals ++ check_signals
end

defp review_comment_actionable?(item, thread_states) do
  item.record.state == "published" and
    case item.snapshot.review_thread_node_id do
      nil -> true
      thread_node_id -> Map.get(thread_states, thread_node_id) == "open"
    end
end
```

This keeps threadless published comments actionable, treats a missing referenced
thread as non-actionable, closes resolved or outdated threaded comments, and
does not add query fanout.

- [x] **Step 4: Update the OpenSpec lifecycle scenario**

Replace the scenario condition in both specs with:

```markdown
- **WHEN** a newer reconciliation marks a review comment pending, minimized, or
  deleted, marks its containing review thread resolved or outdated, or marks a
  previously failing check non-failing
```

- [x] **Step 5: Run the focused test to verify GREEN**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/github_integration/product_mapping_test.exs'`

Expected: all product-mapping tests pass.

- [x] **Step 6: Commit the independently testable change**

```bash
git add test/office_graph/github_integration/product_mapping_test.exs lib/office_graph/github_integration/reconciler.ex openspec/specs/github-review-integration/spec.md openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md
git commit -m "fix: close resolved GitHub review work"
```

### Task 2: Reject Replies To Non-Published Review Comments

**Files:**
- Modify: `test/office_graph/github_integration/outbound_commands_test.exs`
- Modify: `lib/office_graph/github_integration/outbound_commands.ex`
- Modify: `openspec/specs/github-review-integration/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md`

**Interfaces:**
- Consumes: `review_target/2`, `ReviewComment.state`, and the existing `{:error, :forbidden}` non-enumerating command error.
- Produces: `require_replyable_review_comment/1`, which returns `:ok` only for `state == "published"`.

- [x] **Step 1: Write the failing outbound-command regression**

Add this outbound-command regression:

```elixir
test "review replies reject non-published targets before enqueue", context do
  Enum.reduce(Enum.with_index(~w(pending minimized deleted), 2), context.comment, fn
    {state, sequence}, comment ->
      updated =
        comment
        |> Ash.Changeset.for_update(:reconcile, %{
          state: state,
          provider_version: "v#{sequence}",
          provider_sequence: sequence,
          operation_id: comment.operation_id
        })
        |> Repo.ash_update!()

      attrs = %{
        installation_id: context.installation.id,
        review_comment_id: updated.id,
        body: "Do not reply to a #{state} comment.",
        expected_provider_version: updated.provider_version
      }

      operation =
        command_operation!(context, :github_review_reply, "reply:#{state}", attrs)

      assert {:error, :forbidden} =
               OutboundCommands.reply_to_review(context.session, operation, attrs)

      updated
  end)

  assert count_jobs_for_worker() == 0
  assert Provider.calls("review_reply", "PRRC_outbound") == 0
end
```

- [x] **Step 2: Run the regression to verify RED**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/github_integration/outbound_commands_test.exs'`

Expected: FAIL because the current target lookup accepts a non-published comment and enqueues an outbound action.

- [x] **Step 3: Enforce eligibility at the target boundary**

Use this target-boundary implementation:

```elixir
defp review_target(session_context, normalized) do
  with {:ok, record} <-
         scoped_target(ReviewComment, normalized.review_comment_id, session_context),
       :ok <- require_replyable_review_comment(record),
       {:ok, extension} <- review_comment_extension(record.id) do
    {:ok, %{record: record, node_id: extension.node_id}}
  end
end

defp require_replyable_review_comment(%ReviewComment{state: "published"}), do: :ok
defp require_replyable_review_comment(_record), do: {:error, :forbidden}
```

This preserves non-enumerating errors and prevents action persistence, credential resolution, or provider access for hidden or deleted targets.

- [x] **Step 4: Add the outbound OpenSpec scenario**

Add this scenario in both GitHub integration specs:

```markdown
#### Scenario: Reply target is no longer published

- **WHEN** an actor requests a reply to a pending, minimized, or deleted review
  comment
- **THEN** Office Graph MUST reject the command before action enqueue,
  credential resolution, or provider access
```

- [x] **Step 5: Run the focused test to verify GREEN**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/github_integration/outbound_commands_test.exs'`

Expected: all outbound-command tests pass.

- [x] **Step 6: Commit the independently testable change**

```bash
git add test/office_graph/github_integration/outbound_commands_test.exs lib/office_graph/github_integration/outbound_commands.ex openspec/specs/github-review-integration/spec.md openspec/changes/archive/2026-07-14-add-github-review-integration/specs/github-review-integration/spec.md
git commit -m "fix: reject replies to inactive review comments"
```

### Task 3: Evaluate Health Against Required GitHub Permissions

**Files:**
- Modify: `test/office_graph/projections/integration_health_test.exs`
- Modify: `lib/office_graph/github_integration/health.ex`
- Modify: `openspec/specs/integration-health/spec.md`
- Modify: `openspec/changes/archive/2026-07-14-add-github-review-integration/specs/integration-health/spec.md`

**Interfaces:**
- Consumes: the current permission snapshot and the outbound commands' required `checks` and `pull_requests` write permissions.
- Produces: `permission_posture/1` with `missing`, `insufficient`, or `configured`, plus `reauthorize_installation` remediation for incomplete required permission grants.

- [x] **Step 1: Write the failing health regression**

Add this projection regression:

```elixir
test "health reports incomplete required permission grants as insufficient" do
  incomplete_permissions = [
    {"unrelated-read", [%{name: "issues", access_level: "read"}]},
    {"pull-requests-only", [%{name: "pull_requests", access_level: "write"}]},
    {"checks-only", [%{name: "checks", access_level: "write"}]},
    {"pull-requests-read", [
      %{name: "checks", access_level: "write"},
      %{name: "pull_requests", access_level: "read"}
    ]}
  ]

  Enum.each(incomplete_permissions, fn {label, permissions} ->
    context = health_context("permissions-#{label}", permissions)

    assert {:ok, health} =
             Projections.integration_health(
               context.bootstrap.session,
               context.installation.id
             )

    assert health.permission_posture == "insufficient"
    assert health.remediation_code == "reauthorize_installation"
  end)
end
```

Change the test helper signature and binding input to:

```elixir
defp health_context(label, permissions \\ [
       %{name: "checks", access_level: "write"},
       %{name: "pull_requests", access_level: "write"}
     ]) do
  {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
  private_key_reference = "test-secret://github/health/#{label}/private-key"

  {:ok, bound} =
    GitHubIntegration.bind_installation(bootstrap.session, %{
      idempotency_key: "bind-health-#{label}",
      external_installation_id: System.unique_integer([:positive]),
      workspace_id: bootstrap.workspace.id,
      app_slug: "office-graph",
      account_login: "Un3qual",
      account_type: "organization",
      service_principal_email: "github-service-health-#{label}@office-graph.local",
      webhook_principal_email: "github-webhook-health-#{label}@office-graph.local",
      webhook_secret_reference: "test-secret://github/health/#{label}/webhook",
      app_private_key_reference: private_key_reference,
      permissions: permissions
    })

  credential = Enum.find(bound.credentials, &(&1.purpose == "app_private_key"))

  %{
    bootstrap: bootstrap,
    installation: bound.installation,
    credential_id: credential.credential_id
  }
end
```

- [x] **Step 2: Run the regression to verify RED**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/projections/integration_health_test.exs'`

Expected: FAIL because the current projection reports any read, write, or admin permission entry as configured.

- [x] **Step 3: Implement the explicit required-permission invariant**

Use this invariant and thread permissions through `view/7` into remediation selection:

```elixir
@required_write_permissions ~w(checks pull_requests)

defp permission_posture([]), do: "missing"

defp permission_posture(permissions) do
  access_by_name = Map.new(permissions, &{&1.name, &1.access_level})

  if Enum.all?(
       @required_write_permissions,
       &(Map.get(access_by_name, &1) in ~w(write admin))
     ),
     do: "configured",
     else: "insufficient"
end

defp remediation_code(
       %{lifecycle_state: "revoked"},
       _permissions,
       _credentials,
       _failures
     ),
     do: "reauthorize_installation"

defp remediation_code(_installation, _permissions, credentials, _failures)
     when credentials == [],
     do: "configure_credentials"

defp remediation_code(_installation, permissions, credentials, failures) do
  cond do
    credential_posture(credentials) != "active" -> "rotate_credentials"
    permission_posture(permissions) != "configured" -> "reauthorize_installation"
    Enum.any?(failures, &(&1.code == "installation_revoked")) ->
      "reauthorize_installation"
    Enum.any?(failures, &(&1.code == "invalid_credential")) -> "rotate_credentials"
    Enum.any?(failures, &(&1.code == "adapter_unavailable")) -> "configure_adapter"
    true -> nil
  end
end
```

- [x] **Step 4: Add the integration-health OpenSpec scenario**

Add this scenario to the canonical and archived integration-health specs:

```markdown
#### Scenario: Required GitHub permissions are incomplete

- **WHEN** an installation permission snapshot lacks write access to checks or
  pull requests
- **THEN** health MUST report an insufficient permission posture and safe
  installation-reauthorization remediation
```

- [x] **Step 5: Run the focused test to verify GREEN**

Run: `nix --extra-experimental-features 'nix-command flakes' develop --command zsh -lc 'mix test test/office_graph/projections/integration_health_test.exs'`

Expected: all integration-health projection tests pass.

- [x] **Step 6: Commit the independently testable change**

```bash
git add test/office_graph/projections/integration_health_test.exs lib/office_graph/github_integration/health.ex openspec/specs/integration-health/spec.md openspec/changes/archive/2026-07-14-add-github-review-integration/specs/integration-health/spec.md
git commit -m "fix: report incomplete GitHub permissions"
```

### Task 4: Verify, Archive The Plan, Push, And Reply

**Files:**
- Move: `docs/superpowers/plans/2026-07-15-github-review-lifecycle-permissions.md` to `docs/superpowers/plans/archive/2026-07-15-github-review-lifecycle-permissions.md`

**Interfaces:**
- Consumes: all three focused fixes and the cached PR thread IDs.
- Produces: a verified pushed branch and three evidence-backed inline thread replies, with no post-push review refresh.

- [x] **Step 1: Run focused integration verification**

Run all three affected test files together and expect zero failures.

- [x] **Step 2: Run repository verification**

Run `mix verify`, `openspec validate --specs --strict`, `git diff --check`, and `mix format --check-formatted` through the project Nix shell. Every command must exit zero.

- [x] **Step 3: Archive this completed plan and commit it**

Move this plan under `docs/superpowers/plans/archive/` using the repository editing workflow, stage it, and commit with `docs: archive GitHub review follow-up plan`.

- [x] **Step 4: Push once**

Push `codex/github-review-integration` to its existing origin branch.

- [x] **Step 5: Reply in the three cached review threads**

Reply to each thread with the root-cause fix, the relevant commit, and focused plus full verification evidence. Do not refresh PR state after the push or replies, per the user's explicit instruction.
