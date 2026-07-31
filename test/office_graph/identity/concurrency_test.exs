defmodule OfficeGraph.Identity.ConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  alias OfficeGraph.Identity

  alias OfficeGraph.Identity.{
    AuthenticationEvent,
    ExternalIdentityLink,
    HumanSessionPersistenceTestAdapter,
    Session
  }

  @provider "authentik"
  @provider_tenant "https://authentik.office-graph.local/application/o/office-graph/"

  require Ash.Query

  test "separate owners consume an OIDC login transaction exactly once" do
    transaction_id =
      with_unboxed_connection(fn ->
        {:ok, transaction_id} =
          Identity.store_oidc_login_transaction(System.system_time(:second) + 600)

        transaction_id
      end)

    results =
      [
        fn -> Identity.consume_oidc_login_transaction(transaction_id) end,
        fn -> Identity.consume_oidc_login_transaction(transaction_id) end
      ]
      |> run_concurrently()

    assert Enum.sort(results) ==
             Enum.sort([:ok, {:error, :invalid_login_transaction}])
  end

  test "separate owners preserve one active external identity when subjects conflict" do
    {bootstrap, attrs} = bootstrap("external-identity")
    subject_suffix = System.unique_integer([:positive])

    try do
      ["first-subject-#{subject_suffix}", "competing-subject-#{subject_suffix}"]
      |> Enum.map(fn subject ->
        fn ->
          Identity.reconcile_oidc_identity(
            claims(bootstrap.principal.email, subject),
            reconciliation_opts()
          )
        end
      end)
      |> run_concurrently()
      |> then(fn results ->
        assert Enum.count(results, &match?({:ok, _linked}, &1)) == 1
        assert Enum.count(results, &(&1 == {:error, :identity_review_required})) == 1
      end)

      links =
        with_unboxed_connection(fn ->
          ExternalIdentityLink
          |> Ash.Query.filter(
            provider == ^@provider and provider_tenant == ^@provider_tenant and
              verified_email == ^bootstrap.principal.email
          )
          |> Ash.read!(authorize?: false)
        end)

      assert Enum.frequencies_by(links, &{&1.status, &1.linking_state}) == %{
               {"active", "linked"} => 1,
               {"review_required", "review_required"} => 1
             }

      assert [active_link] = Enum.filter(links, &(&1.status == "active"))
      assert active_link.principal_id == bootstrap.principal.id
    after
      cleanup(attrs)
    end
  end

  test "separate owners serialize same-scope human session replacement" do
    {bootstrap, attrs} = bootstrap("human-session")
    linked = link_identity(bootstrap, "session-subject")

    try do
      results =
        ["first-login", "competing-login"]
        |> Enum.map(fn subject ->
          fn -> issue_session(linked, bootstrap, subject) end
        end)
        |> run_concurrently()

      assert Enum.all?(results, &match?({:ok, _issued}, &1))

      {sessions, events} =
        with_unboxed_connection(fn ->
          sessions =
            Session
            |> Ash.Query.filter(
              principal_id == ^bootstrap.principal.id and purpose == "human_web"
            )
            |> Ash.read!(authorize?: false)

          events =
            AuthenticationEvent
            |> Ash.Query.filter(principal_id == ^bootstrap.principal.id)
            |> Ash.read!(authorize?: false)

          {sessions, events}
        end)

      assert length(sessions) == 2
      assert Enum.count(sessions, &is_nil(&1.revoked_at)) == 1
      assert Enum.count(sessions, &match?(%DateTime{}, &1.revoked_at)) == 1
      assert Enum.frequencies_by(events, & &1.event) == %{"login" => 2, "revocation" => 1}
    after
      cleanup(attrs)
    end
  end

  test "human session issuance rolls back replacement when login evidence fails" do
    {bootstrap, attrs} = bootstrap("session-atomicity")
    linked = link_identity(bootstrap, "atomic-session-subject")

    try do
      first =
        with_unboxed_connection(fn ->
          {:ok, issued} = issue_session(linked, bootstrap, "first-login")
          issued
        end)

      HumanSessionPersistenceTestAdapter.configure!(issue_event: {:error, :database_unavailable})

      assert {:error, :identity_storage_unavailable} =
               with_unboxed_connection(fn ->
                 issue_session(linked, bootstrap, "failed-replacement")
               end)

      {sessions, events} =
        with_unboxed_connection(fn ->
          sessions =
            Session
            |> Ash.Query.filter(
              principal_id == ^bootstrap.principal.id and purpose == "human_web"
            )
            |> Ash.read!(authorize?: false)

          events =
            AuthenticationEvent
            |> Ash.Query.filter(principal_id == ^bootstrap.principal.id)
            |> Ash.read!(authorize?: false)

          {sessions, events}
        end)

      assert [%Session{id: session_id, revoked_at: nil}] = sessions
      assert session_id == first.session.id
      assert Enum.map(events, &{&1.event, &1.trace_id}) == [{"login", "first-login"}]
    after
      cleanup(attrs)
    end
  end

  defp bootstrap(label) do
    suffix = System.unique_integer([:positive])

    attrs = [
      organization_name: "Identity Concurrency #{label} #{suffix}",
      organization_slug: "identity-concurrency-#{label}-#{suffix}",
      workspace_name: "Identity Concurrency Workspace #{suffix}",
      workspace_slug: "identity-concurrency-workspace-#{label}-#{suffix}",
      initiative_name: "Identity Concurrency Initiative #{suffix}",
      initiative_slug: "identity-concurrency-initiative-#{label}-#{suffix}",
      owner_email: "identity-concurrency-#{label}-#{suffix}@example.test",
      owner_name: "Identity Concurrency Owner #{suffix}"
    ]

    bootstrap =
      with_unboxed_connection(fn ->
        {:ok, bootstrap} = Foundation.bootstrap_local_owner(attrs)
        bootstrap
      end)

    {bootstrap, attrs}
  end

  defp link_identity(bootstrap, subject) do
    with_unboxed_connection(fn ->
      {:ok, linked} =
        Identity.reconcile_oidc_identity(
          claims(bootstrap.principal.email, subject),
          reconciliation_opts()
        )

      linked
    end)
  end

  defp issue_session(linked, bootstrap, trace_id) do
    Identity.issue_human_session(
      linked.principal,
      linked.external_identity_link,
      %{
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id
      },
      authentication_method: "oidc",
      source_surface: "web",
      trace_id: trace_id,
      ttl_seconds: 3_600
    )
  end

  defp claims(email, subject) do
    %{
      "sub" => subject,
      "email" => email,
      "email_verified" => true,
      "name" => "OIDC User"
    }
  end

  defp reconciliation_opts do
    [
      provider: @provider,
      provider_tenant: @provider_tenant,
      account_linking_policy: :verified_email_existing_principal
    ]
  end

  defp cleanup(attrs) do
    with_unboxed_connection(fn ->
      ConcurrencyCleanup.cleanup_bootstrap_scope!(attrs[:organization_slug], attrs[:owner_email])
    end)
  end
end
