defmodule OfficeGraph.Identity.HumanAuthenticationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.Authorization.RoleAssignment
  alias OfficeGraph.Foundation

  alias OfficeGraph.Identity.{
    AuthenticationEvent,
    ExternalIdentityLink,
    Principal,
    Session
  }

  alias OfficeGraph.Identity

  require Ash.Query

  @provider "authentik"
  @provider_tenant "https://authentik.office-graph.local/application/o/office-graph/"

  setup do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_slug: unique("human-auth-org"),
        workspace_slug: unique("human-auth-workspace"),
        initiative_slug: unique("human-auth-initiative"),
        owner_email: "#{unique("human-auth-owner")}@example.test"
      )

    %{bootstrap: bootstrap}
  end

  describe "reconcile_oidc_identity/2" do
    test "links one verified existing human principal and reuses the exact subject", %{
      bootstrap: bootstrap
    } do
      claims = claims(bootstrap.principal.email, "subject-1")

      assert {:ok, first} = Identity.reconcile_oidc_identity(claims, reconciliation_opts())
      assert first.principal.id == bootstrap.principal.id
      assert first.external_identity_link.status == "active"
      assert first.external_identity_link.linking_state == "linked"
      assert first.external_identity_link.provider == @provider
      assert first.external_identity_link.provider_tenant == @provider_tenant
      assert first.external_identity_link.subject == "subject-1"
      assert first.external_identity_link.verified_email == bootstrap.principal.email

      updated_claims =
        claims(bootstrap.principal.email, "subject-1")
        |> Map.put("name", "Updated display name")

      assert {:ok, second} =
               Identity.reconcile_oidc_identity(updated_claims, reconciliation_opts())

      assert second.principal.id == bootstrap.principal.id
      assert second.external_identity_link.id == first.external_identity_link.id

      assert DateTime.compare(
               second.external_identity_link.last_authenticated_at,
               first.external_identity_link.last_authenticated_at
             ) in [:eq, :gt]
    end

    test "refuses an unverified identifier without creating a link", %{bootstrap: bootstrap} do
      claims =
        bootstrap.principal.email
        |> claims("unverified-subject")
        |> Map.put("email_verified", false)

      assert {:error, :unverified_identifier} =
               Identity.reconcile_oidc_identity(claims, reconciliation_opts())

      refute link_for_subject("unverified-subject")
    end

    test "matches the normalized verified identifier to one existing human principal" do
      owner_email = "  #{unique("Normalized.Owner")}@Example.TEST  "

      {:ok, bootstrap} =
        Foundation.bootstrap_local_owner(
          organization_slug: unique("normalized-owner-org"),
          workspace_slug: unique("normalized-owner-workspace"),
          initiative_slug: unique("normalized-owner-initiative"),
          owner_email: owner_email
        )

      normalized_email = owner_email |> String.trim() |> String.downcase()

      assert {:ok, linked} =
               Identity.reconcile_oidc_identity(
                 claims(normalized_email, "normalized-owner-subject"),
                 reconciliation_opts()
               )

      assert linked.principal.id == bootstrap.principal.id
      assert linked.external_identity_link.verified_email == normalized_email
    end

    test "persists review when multiple principals own the normalized identifier" do
      normalized_email = "#{unique("ambiguous-owner")}@example.test"

      for email <- [String.upcase(normalized_email), " #{normalized_email} "] do
        Ash.create!(
          Principal,
          %{
            id: Ecto.UUID.generate(),
            email: email,
            kind: "human",
            status: "active"
          },
          action: :create,
          authorize?: false
        )
      end

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(
                 claims(normalized_email, "ambiguous-owner-subject"),
                 reconciliation_opts()
               )

      assert %ExternalIdentityLink{
               principal_id: nil,
               status: "review_required",
               review_reason: "ambiguous_verified_identifier"
             } = link_for_subject("ambiguous-owner-subject")
    end

    test "persists a stable review state for an unknown verified identifier" do
      claims = claims("#{unique("unknown")}@example.test", "unknown-subject")

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(claims, reconciliation_opts())

      first_link = link_for_subject("unknown-subject")

      assert %ExternalIdentityLink{
               principal_id: nil,
               status: "review_required",
               linking_state: "review_required",
               review_reason: "unlinked_verified_identifier"
             } = first_link

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(claims, reconciliation_opts())

      assert link_for_subject("unknown-subject").id == first_link.id
    end

    test "persists review instead of silently linking a second subject to the same identifier", %{
      bootstrap: bootstrap
    } do
      assert {:ok, linked} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "first-subject"),
                 reconciliation_opts()
               )

      assert linked.principal.id == bootstrap.principal.id

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "conflicting-subject"),
                 reconciliation_opts()
               )

      assert %ExternalIdentityLink{
               principal_id: nil,
               status: "review_required",
               review_reason: "verified_identifier_conflict"
             } = link_for_subject("conflicting-subject")
    end

    test "rejects disabled links and principals", %{bootstrap: bootstrap} do
      assert {:ok, linked} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "disabled-subject"),
                 reconciliation_opts()
               )

      linked.external_identity_link
      |> Ash.Changeset.for_update(:set_lifecycle, %{
        status: "disabled",
        disabled_at: DateTime.utc_now()
      })
      |> Ash.update!(authorize?: false)

      assert {:error, :identity_disabled} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "disabled-subject"),
                 reconciliation_opts()
               )

      linked.external_identity_link
      |> Ash.Changeset.for_update(:set_lifecycle, %{status: "active", disabled_at: nil})
      |> Ash.update!(authorize?: false)

      bootstrap.principal
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"})
      |> Ash.update!(authorize?: false)

      assert {:error, :principal_disabled} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "disabled-subject"),
                 reconciliation_opts()
               )
    end

    test "does not turn external group or role claims into authorization facts", %{
      bootstrap: bootstrap
    } do
      before_count = role_assignment_count(bootstrap.principal.id)

      claims =
        bootstrap.principal.email
        |> claims("claims-have-no-authority")
        |> Map.merge(%{
          "groups" => ["owner", "workspace-admin"],
          "roles" => ["verification.waive", "system.conformance"]
        })

      assert {:ok, _linked} = Identity.reconcile_oidc_identity(claims, reconciliation_opts())
      assert role_assignment_count(bootstrap.principal.id) == before_count
    end
  end

  describe "human session lifecycle" do
    setup %{bootstrap: bootstrap} do
      {:ok, linked} =
        Identity.reconcile_oidc_identity(
          claims(bootstrap.principal.email, unique("session-subject")),
          reconciliation_opts()
        )

      %{linked: linked}
    end

    test "issues an expiry-bearing thin session and resolves its context", %{
      bootstrap: bootstrap,
      linked: linked
    } do
      assert {:ok, issued} = issue_session(linked, bootstrap, "issue-session")

      assert %Session{
               purpose: "human_web",
               authentication_method: "oidc",
               source_surface: "web",
               trace_id: "issue-session"
             } = issued.session

      assert issued.session.external_identity_link_id == linked.external_identity_link.id
      assert DateTime.compare(issued.session.expires_at, issued.session.issued_at) == :gt
      assert issued.session_context.session_id == issued.session.id
      assert issued.session_context.principal_id == linked.principal.id
      assert issued.session_context.external_identity_link_id == linked.external_identity_link.id
      assert issued.session_context.authentication_method == "oidc"
      assert issued.session_context.capabilities == MapSet.new()
      refute issued.session_context.trusted?

      assert {:ok, resolved} = Identity.resolve_human_session(issued.session.id)
      assert resolved == issued.session_context
    end

    test "revokes the previous active same-scope session before replacement", %{
      bootstrap: bootstrap,
      linked: linked
    } do
      assert {:ok, first} = issue_session(linked, bootstrap, "replacement-first")
      assert {:ok, second} = issue_session(linked, bootstrap, "replacement-second")

      assert first.session.id != second.session.id
      assert {:error, :invalid_session} = Identity.resolve_human_session(first.session.id)
      assert {:ok, resolved} = Identity.resolve_human_session(second.session.id)
      assert resolved == second.session_context

      revoked = Ash.get!(Session, first.session.id, authorize?: false)
      assert revoked.revoked_at
    end

    test "rejects expired, revoked, disabled-link, and disabled-principal sessions", %{
      bootstrap: bootstrap,
      linked: linked
    } do
      expired =
        create_human_session!(
          linked,
          bootstrap,
          issued_at: DateTime.add(DateTime.utc_now(), -7_200, :second),
          expires_at: DateTime.add(DateTime.utc_now(), -3_600, :second),
          trace_id: "expired-session"
        )

      assert {:error, :invalid_session} = Identity.resolve_human_session(expired.id)

      assert {:ok, revocable} = issue_session(linked, bootstrap, "revoked-session")
      assert :ok = Identity.revoke_human_session(revocable.session.id, trace_id: "logout")
      assert {:error, :invalid_session} = Identity.resolve_human_session(revocable.session.id)

      assert {:ok, link_session} = issue_session(linked, bootstrap, "disabled-link-session")

      linked.external_identity_link
      |> Ash.Changeset.for_update(:set_lifecycle, %{
        status: "disabled",
        disabled_at: DateTime.utc_now()
      })
      |> Ash.update!(authorize?: false)

      assert {:error, :invalid_session} =
               Identity.resolve_human_session(link_session.session.id)

      assert {:error, :identity_disabled} =
               issue_session(linked, bootstrap, "disabled-link-new-session")

      linked.external_identity_link
      |> Ash.Changeset.for_update(:set_lifecycle, %{status: "active", disabled_at: nil})
      |> Ash.update!(authorize?: false)

      assert {:ok, principal_session} =
               issue_session(linked, bootstrap, "disabled-principal-session")

      linked.principal
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"})
      |> Ash.update!(authorize?: false)

      assert {:error, :invalid_session} =
               Identity.resolve_human_session(principal_session.session.id)

      assert {:error, :principal_disabled} =
               issue_session(linked, bootstrap, "disabled-principal-new-session")
    end

    test "records bounded login and logout evidence without provider secrets", %{
      bootstrap: bootstrap,
      linked: linked
    } do
      assert {:ok, issued} = issue_session(linked, bootstrap, "login-evidence")
      assert :ok = Identity.revoke_human_session(issued.session.id, trace_id: "logout-evidence")

      events =
        AuthenticationEvent
        |> Ash.Query.filter(session_id == ^issued.session.id)
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!(authorize?: false)

      assert Enum.map(events, &{&1.event, &1.result, &1.trace_id}) == [
               {"login", "succeeded", "login-evidence"},
               {"logout", "succeeded", "logout-evidence"}
             ]

      for event <- events do
        refute Map.has_key?(event, :authorization_code)
        refute Map.has_key?(event, :access_token)
        refute Map.has_key?(event, :refresh_token)
        refute Map.has_key?(event, :id_token)
        refute Map.has_key?(event, :claims)
        refute Map.has_key?(event, :cookie)
      end
    end
  end

  defp reconciliation_opts do
    [
      provider: @provider,
      provider_tenant: @provider_tenant,
      account_linking_policy: :verified_email_existing_principal
    ]
  end

  defp claims(email, subject) do
    %{
      "sub" => subject,
      "email" => email,
      "email_verified" => true,
      "name" => "OIDC User"
    }
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

  defp create_human_session!(linked, bootstrap, attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      principal_id: linked.principal.id,
      external_identity_link_id: linked.external_identity_link.id,
      organization_id: bootstrap.organization.id,
      workspace_id: bootstrap.workspace.id,
      purpose: "human_web",
      authentication_method: "oidc",
      source_surface: "web",
      trace_id: unique("human-session"),
      issued_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), 3_600, :second)
    }

    Session
    |> Ash.Changeset.for_create(:create, Map.merge(defaults, Map.new(attrs)))
    |> Ash.create!(authorize?: false)
  end

  defp link_for_subject(subject) do
    ExternalIdentityLink
    |> Ash.Query.filter(
      provider == ^@provider and provider_tenant == ^@provider_tenant and
        subject == ^subject
    )
    |> Ash.read_one!(authorize?: false)
  end

  defp role_assignment_count(principal_id) do
    RoleAssignment
    |> Ash.Query.filter(principal_id == ^principal_id)
    |> Ash.count!(authorize?: false)
  end

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
