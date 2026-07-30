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
  alias OfficeGraph.QueryCounter

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

    test "keeps an exact subject binding when its verified email changes without conflict", %{
      bootstrap: bootstrap
    } do
      assert {:ok, first} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "changed-email-subject"),
                 reconciliation_opts()
               )

      assert {:ok, second} =
               Identity.reconcile_oidc_identity(
                 claims("#{unique("unclaimed-email")}@example.test", "changed-email-subject"),
                 reconciliation_opts()
               )

      assert second.principal.id == bootstrap.principal.id
      assert second.external_identity_link.id == first.external_identity_link.id
      assert second.external_identity_link.status == "active"
      assert second.external_identity_link.verified_email == bootstrap.principal.email
    end

    test "moves a known subject to review when its new verified email belongs to another principal",
         %{bootstrap: bootstrap} do
      subject = "known-subject-principal-conflict"

      assert {:ok, linked} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, subject),
                 reconciliation_opts()
               )

      conflicting_email = "#{unique("principal-conflict")}@example.test"

      conflicting_principal =
        Ash.create!(
          Principal,
          %{
            id: Ecto.UUID.generate(),
            email: conflicting_email,
            kind: "human",
            status: "active"
          },
          action: :create,
          authorize?: false
        )

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(
                 claims(conflicting_principal.email, subject),
                 reconciliation_opts()
               )

      assert %ExternalIdentityLink{
               id: link_id,
               principal_id: principal_id,
               verified_email: verified_email,
               status: "review_required",
               linking_state: "review_required",
               review_reason: "verified_identifier_conflict"
             } = link_for_subject(subject)

      assert link_id == linked.external_identity_link.id
      assert principal_id == bootstrap.principal.id
      assert verified_email == bootstrap.principal.email

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, subject),
                 reconciliation_opts()
               )
    end

    test "moves a known subject to review when its new verified email has an incompatible link",
         %{bootstrap: bootstrap} do
      subject = "known-subject-link-conflict"

      assert {:ok, linked} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, subject),
                 reconciliation_opts()
               )

      conflicting_email = "#{unique("link-conflict")}@example.test"

      Ash.create!(
        ExternalIdentityLink,
        %{
          id: Ecto.UUID.generate(),
          provider: @provider,
          provider_tenant: @provider_tenant,
          subject: "incompatible-subject",
          verified_email: conflicting_email,
          status: "review_required",
          linking_state: "review_required",
          review_reason: "unlinked_verified_identifier"
        },
        action: :create,
        authorize?: false
      )

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(
                 claims(conflicting_email, subject),
                 reconciliation_opts()
               )

      assert %ExternalIdentityLink{
               id: link_id,
               principal_id: principal_id,
               verified_email: verified_email,
               status: "review_required",
               linking_state: "review_required",
               review_reason: "verified_identifier_conflict"
             } = link_for_subject(subject)

      assert link_id == linked.external_identity_link.id
      assert principal_id == bootstrap.principal.id
      assert verified_email == bootstrap.principal.email
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

    test "persists review for an inactive human matched by an unknown subject", %{
      bootstrap: bootstrap
    } do
      bootstrap.principal
      |> Ash.Changeset.for_update(:set_status, %{status: "inactive"})
      |> Ash.update!(authorize?: false)

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "inactive-human-subject"),
                 reconciliation_opts()
               )

      assert %ExternalIdentityLink{
               principal_id: nil,
               status: "review_required",
               linking_state: "review_required",
               review_reason: "ineligible_principal"
             } = link_for_subject("inactive-human-subject")
    end

    test "isolates a conflicting second subject without disabling the established subject", %{
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

      assert {:ok, reauthenticated} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "first-subject"),
                 reconciliation_opts()
               )

      assert reauthenticated.external_identity_link.id == linked.external_identity_link.id
    end

    test "requires review when another provider already has the verified identifier", %{
      bootstrap: bootstrap
    } do
      Ash.create!(
        ExternalIdentityLink,
        %{
          id: Ecto.UUID.generate(),
          provider: "legacy-idp",
          provider_tenant: "https://legacy-idp.example.test/",
          subject: "legacy-subject",
          verified_email: bootstrap.principal.email,
          status: "review_required",
          linking_state: "review_required",
          review_reason: "unlinked_verified_identifier"
        },
        action: :create,
        authorize?: false
      )

      assert {:error, :identity_review_required} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "current-provider-subject"),
                 reconciliation_opts()
               )

      assert %ExternalIdentityLink{
               principal_id: nil,
               status: "review_required",
               review_reason: "verified_identifier_conflict"
             } = link_for_subject("current-provider-subject")
    end

    test "rejects disabled links and principals", %{bootstrap: bootstrap} do
      assert {:ok, linked} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "disabled-subject"),
                 reconciliation_opts()
               )

      disabled_link =
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

      disabled_link
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

    test "rejects an unsupported linking policy without creating review state", %{
      bootstrap: bootstrap
    } do
      assert {:error, :unsupported_account_linking_policy} =
               Identity.reconcile_oidc_identity(
                 claims(bootstrap.principal.email, "unsupported-policy-subject"),
                 provider: @provider,
                 provider_tenant: @provider_tenant,
                 account_linking_policy: :unsupported
               )

      refute link_for_subject("unsupported-policy-subject")
    end
  end

  describe "principal lifecycle" do
    test "create rejects an unsupported lifecycle state" do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(
                 Principal,
                 %{
                   id: Ecto.UUID.generate(),
                   email: "#{unique("invalid-principal-create")}@example.test",
                   kind: "human",
                   status: "compromised"
                 },
                 action: :create,
                 authorize?: false
               )
    end

    test "status updates reject an unsupported lifecycle state", %{bootstrap: bootstrap} do
      assert {:error, %Ash.Error.Invalid{}} =
               bootstrap.principal
               |> Ash.Changeset.for_update(:set_status, %{status: "compromised"})
               |> Ash.update(authorize?: false)

      assert Ash.get!(Principal, bootstrap.principal.id, authorize?: false).status == "active"
    end
  end

  describe "external identity link lifecycle" do
    test "create rejects unsupported lifecycle values" do
      for invalid <- [%{status: "compromised"}, %{linking_state: "pending"}] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Ash.create(
                   ExternalIdentityLink,
                   external_identity_link_attrs(invalid),
                   action: :create,
                   authorize?: false
                 )
      end
    end

    test "lifecycle updates reject unsupported values", %{bootstrap: bootstrap} do
      {:ok, linked} =
        Identity.reconcile_oidc_identity(
          claims(bootstrap.principal.email, unique("lifecycle-subject")),
          reconciliation_opts()
        )

      for invalid <- [%{status: "compromised"}, %{linking_state: "pending"}] do
        assert {:error, %Ash.Error.Invalid{}} =
                 linked.external_identity_link
                 |> Ash.Changeset.for_update(:set_lifecycle, invalid)
                 |> Ash.update(authorize?: false)
      end

      persisted =
        Ash.get!(ExternalIdentityLink, linked.external_identity_link.id, authorize?: false)

      assert persisted.status == "active"
      assert persisted.linking_state == "linked"
    end

    test "lifecycle updates cannot reassign identity ownership", %{bootstrap: bootstrap} do
      {:ok, linked} =
        Identity.reconcile_oidc_identity(
          claims(bootstrap.principal.email, unique("ownership-subject")),
          reconciliation_opts()
        )

      replacement =
        Ash.create!(
          Principal,
          %{
            email: "#{unique("replacement-principal")}@example.test",
            kind: "human",
            status: "active"
          },
          action: :create,
          authorize?: false
        )

      assert {:error, %Ash.Error.Invalid{}} =
               linked.external_identity_link
               |> Ash.Changeset.for_update(:set_lifecycle, %{
                 status: "disabled",
                 principal_id: replacement.id
               })
               |> Ash.update(authorize?: false)

      persisted =
        Ash.get!(ExternalIdentityLink, linked.external_identity_link.id, authorize?: false)

      assert persisted.status == "active"
      assert persisted.principal_id == bootstrap.principal.id
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

    test "validates a governed human session with one session-row read", %{
      bootstrap: bootstrap,
      linked: linked
    } do
      assert {:ok, issued} = issue_session(linked, bootstrap, "validate-session-context")

      {result, queries} =
        QueryCounter.count(fn ->
          Identity.validate_session_context(issued.session_context)
        end)

      assert result == :ok
      assert QueryCounter.source_count(queries, "sessions") == 1
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

      events =
        AuthenticationEvent
        |> Ash.Query.filter(session_id == ^first.session.id)
        |> Ash.Query.sort(inserted_at: :asc)
        |> Ash.read!(authorize?: false)

      assert Enum.map(events, &{&1.event, &1.result, &1.reason, &1.trace_id}) == [
               {"login", "succeeded", "login_completed", "replacement-first"},
               {"revocation", "succeeded", "session_replaced", "replacement-second"}
             ]
    end

    test "classifies malformed workspace identifiers as an invalid scope", %{
      bootstrap: bootstrap,
      linked: linked
    } do
      assert {:error, :invalid_scope} =
               Identity.issue_human_session(
                 linked.principal,
                 linked.external_identity_link,
                 %{
                   organization_id: bootstrap.organization.id,
                   workspace_id: "not-a-uuid"
                 },
                 authentication_method: "oidc",
                 source_surface: "web",
                 trace_id: "malformed-workspace"
               )
    end

    test "classifies malformed logout session identifiers as invalid" do
      assert {:error, :invalid_session} =
               Identity.revoke_human_session("not-a-uuid", trace_id: "malformed-logout")
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

      assert {:error, :invalid_session} =
               Identity.resolve_human_session(expired.id,
                 trace_id: "expired-session-reuse",
                 source_surface: "web"
               )

      assert {:ok, revocable} = issue_session(linked, bootstrap, "revoked-session")
      assert :ok = Identity.revoke_human_session(revocable.session.id, trace_id: "logout")

      assert {:error, :invalid_session} =
               Identity.resolve_human_session(revocable.session.id,
                 trace_id: "revoked-session-reuse",
                 source_surface: "web"
               )

      assert {:ok, link_session} = issue_session(linked, bootstrap, "disabled-link-session")

      disabled_link =
        linked.external_identity_link
        |> Ash.Changeset.for_update(:set_lifecycle, %{
          status: "disabled",
          disabled_at: DateTime.utc_now()
        })
        |> Ash.update!(authorize?: false)

      assert {:error, :invalid_session} =
               Identity.resolve_human_session(link_session.session.id,
                 trace_id: "disabled-link-session-reuse",
                 source_surface: "web"
               )

      assert {:error, :identity_disabled} =
               issue_session(linked, bootstrap, "disabled-link-new-session")

      disabled_link
      |> Ash.Changeset.for_update(:set_lifecycle, %{status: "active", disabled_at: nil})
      |> Ash.update!(authorize?: false)

      assert {:ok, principal_session} =
               issue_session(linked, bootstrap, "disabled-principal-session")

      linked.principal
      |> Ash.Changeset.for_update(:set_status, %{status: "disabled"})
      |> Ash.update!(authorize?: false)

      assert {:error, :invalid_session} =
               Identity.resolve_human_session(principal_session.session.id,
                 trace_id: "disabled-principal-session-reuse",
                 source_surface: "web"
               )

      assert {:error, :principal_disabled} =
               issue_session(linked, bootstrap, "disabled-principal-new-session")

      rejected_events =
        AuthenticationEvent
        |> Ash.Query.filter(event == "session_validation" and result == "rejected")
        |> Ash.read!(authorize?: false)
        |> Map.new(&{&1.session_id, &1})

      principal_id = linked.principal.id
      external_identity_link_id = linked.external_identity_link.id

      assert %{
               reason: "session_expired",
               trace_id: "expired-session-reuse",
               principal_id: ^principal_id,
               external_identity_link_id: ^external_identity_link_id
             } = rejected_events[expired.id]

      assert %{
               reason: "session_revoked",
               trace_id: "revoked-session-reuse"
             } = rejected_events[revocable.session.id]

      assert %{
               reason: "identity_disabled",
               trace_id: "disabled-link-session-reuse"
             } = rejected_events[link_session.session.id]

      assert %{
               reason: "principal_disabled",
               trace_id: "disabled-principal-session-reuse"
             } = rejected_events[principal_session.session.id]
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

      assert Enum.map(events, &{&1.event, &1.result, &1.reason, &1.trace_id}) == [
               {"login", "succeeded", "login_completed", "login-evidence"},
               {"logout", "succeeded", "user_logout", "logout-evidence"}
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

    test "classifies malformed authentication evidence as invalid input" do
      assert {:error, :invalid_authentication_event} =
               Identity.record_authentication_event(%{})
    end

    test "rejects authentication evidence without a bounded reason" do
      assert {:error, :invalid_authentication_event} =
               Identity.record_authentication_event(%{
                 event: "login",
                 result: "succeeded",
                 authentication_method: "oidc",
                 source_surface: "web",
                 trace_id: "missing-reason"
               })
    end

    test "rejects authentication evidence with an unrecognized reason" do
      assert {:error, :invalid_authentication_event} =
               Identity.record_authentication_event(%{
                 event: "login",
                 result: "rejected",
                 reason: "provider response contained sensitive details",
                 authentication_method: "oidc",
                 source_surface: "web",
                 trace_id: "unrecognized-reason"
               })

      assert [] =
               AuthenticationEvent
               |> Ash.Query.filter(trace_id == "unrecognized-reason")
               |> Ash.read!(authorize?: false)
    end

    test "rejects authentication evidence with unsupported event or result values" do
      for {trace_id, override} <- [
            {"unsupported-event", %{event: "token_teleported"}},
            {"unsupported-result", %{result: "maybe"}}
          ] do
        attrs =
          Map.merge(
            %{
              event: "login",
              result: "rejected",
              reason: "authentication_failed",
              authentication_method: "oidc",
              source_surface: "web",
              trace_id: trace_id
            },
            override
          )

        assert {:error, :invalid_authentication_event} =
                 Identity.record_authentication_event(attrs)

        assert [] =
                 AuthenticationEvent
                 |> Ash.Query.filter(trace_id == ^trace_id)
                 |> Ash.read!(authorize?: false)
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

  defp external_identity_link_attrs(overrides) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        provider: @provider,
        provider_tenant: @provider_tenant,
        subject: unique("lifecycle-create-subject"),
        verified_email: "#{unique("lifecycle-create")}@example.test",
        status: "review_required",
        linking_state: "review_required",
        review_reason: "unlinked_verified_identifier"
      },
      overrides
    )
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
