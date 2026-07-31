defmodule OfficeGraph.Identity.HumanSessions do
  @moduledoc false

  alias OfficeGraph.Identity.{
    AuthenticationEvent,
    ExternalIdentityLink,
    HumanSessionPersistence,
    Principal,
    Session,
    SessionContext
  }

  alias OfficeGraph.Tenancy

  @purpose "human_web"

  @storage_exceptions [
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error
  ]

  def issue(
        %Principal{kind: "human", status: "active"} = principal,
        %ExternalIdentityLink{
          principal_id: principal_id,
          status: "active",
          linking_state: "linked"
        } = external_identity_link,
        %{organization_id: organization_id, workspace_id: workspace_id},
        opts
      )
      when principal_id == principal.id and is_binary(organization_id) and
             is_binary(workspace_id) and is_list(opts) do
    with {:ok, attrs} <- session_attrs(opts),
         :ok <- validate_workspace_scope(organization_id, workspace_id) do
      with_storage_boundary(fn ->
        Session
        |> Ash.ActionInput.for_action(:issue_human_session, %{
          principal_id: principal.id,
          external_identity_link_id: external_identity_link.id,
          organization_id: organization_id,
          workspace_id: workspace_id,
          authentication_method: attrs.authentication_method,
          enterprise_connection_id: attrs.enterprise_connection_id,
          source_surface: attrs.source_surface,
          trace_id: attrs.trace_id,
          ttl_seconds: attrs.ttl_seconds
        })
        |> Ash.run_action(authorize?: false)
        |> normalize_issue_result()
      end)
    end
  end

  def issue(_principal, _link, _scope, _opts), do: {:error, :invalid_identity}

  def resolve(session_id), do: resolve(session_id, [])

  def resolve(session_id, opts) when is_binary(session_id) and is_list(opts) do
    with :ok <- HumanSessionPersistence.before_access(:resolve),
         {:ok, %Session{} = session} <-
           Ash.get(Session, session_id, authorize?: false, not_found_error?: false),
         :ok <- validate_session_record(session),
         {:ok, principal} <-
           validate_principal(
             Ash.get(Principal, session.principal_id,
               authorize?: false,
               not_found_error?: false
             ),
             session
           ),
         {:ok, external_identity_link} <-
           validate_external_identity_link(
             Ash.get(ExternalIdentityLink, session.external_identity_link_id,
               authorize?: false,
               not_found_error?: false
             ),
             session
           ),
         :ok <-
           validate_resolved_scope(
             validate_workspace_scope(session.organization_id, session.workspace_id),
             session
           ) do
      {:ok, context(session, principal, external_identity_link)}
    else
      {:reject, session, reason} ->
        reject_session(session, reason, opts)

      {:error, :identity_storage_unavailable} ->
        {:error, :identity_storage_unavailable}

      {:error, %Ash.Error.Invalid{}} ->
        {:error, :invalid_session}

      {:error, storage_error} ->
        if Ash.Error.ash_error?(storage_error) do
          {:error, :identity_storage_unavailable}
        else
          {:error, :invalid_session}
        end

      _invalid_or_unavailable ->
        {:error, :invalid_session}
    end
  end

  def resolve(_session_id, _opts), do: {:error, :invalid_session}

  def authentication_method(session_id) when is_binary(session_id) do
    case Ash.Type.UUID.cast_input(session_id, []) do
      {:ok, session_id} ->
        with_storage_boundary(fn ->
          case Ash.get(Session, session_id, authorize?: false, not_found_error?: false) do
            {:ok, %Session{purpose: @purpose, authentication_method: method}}
            when is_binary(method) ->
              {:ok, method}

            {:ok, _missing_or_wrong_purpose} ->
              {:error, :invalid_session}

            {:error, _storage_error} ->
              {:error, :identity_storage_unavailable}
          end
        end)

      :error ->
        {:error, :invalid_session}
    end
  end

  def authentication_method(_session_id), do: {:error, :invalid_session}

  def revoke(session_id, opts) when is_binary(session_id) and is_list(opts) do
    trace_id = Keyword.get(opts, :trace_id)

    if present?(trace_id) do
      case Ash.Type.UUID.cast_input(session_id, []) do
        {:ok, session_id} ->
          with_storage_boundary(fn ->
            with :ok <- HumanSessionPersistence.before_access(:revoke) do
              Session
              |> Ash.ActionInput.for_action(:revoke_human_session, %{
                session_id: session_id,
                trace_id: trace_id
              })
              |> Ash.run_action(authorize?: false)
              |> normalize_revoke_result()
            end
          end)

        :error ->
          {:error, :invalid_session}
      end
    else
      {:error, :invalid_trace}
    end
  end

  def revoke(_session_id, _opts), do: {:error, :invalid_session}

  def record_event(attrs) when is_map(attrs) do
    with :ok <- HumanSessionPersistence.before_access(:event) do
      AuthenticationEvent
      |> Ash.Changeset.for_create(:create, event_attrs(attrs))
      |> Ash.create(authorize?: false)
      |> case do
        {:ok, event} -> {:ok, event}
        {:error, %Ash.Error.Invalid{}} -> {:error, :invalid_authentication_event}
        {:error, _storage_error} -> {:error, :identity_storage_unavailable}
      end
    else
      {:error, _storage_error} -> {:error, :identity_storage_unavailable}
    end
  end

  def record_event(_attrs), do: {:error, :invalid_authentication_event}

  def reject(%SessionContext{} = session_context, reason, opts)
      when is_binary(reason) and is_list(opts) do
    trace_id = Keyword.get(opts, :trace_id)
    source_surface = Keyword.get(opts, :source_surface)

    if present?(trace_id) and present?(source_surface) do
      with :ok <- HumanSessionPersistence.before_access(:event) do
        with_storage_boundary(fn ->
          Session
          |> Ash.ActionInput.for_action(:reject_human_session, %{
            session_id: session_context.session_id,
            reason: reason,
            source_surface: source_surface,
            trace_id: trace_id
          })
          |> Ash.run_action(authorize?: false)
          |> normalize_reject_result()
        end)
      end
    else
      {:error, :invalid_session}
    end
  end

  def reject(_session_context, _reason, _opts), do: {:error, :invalid_session}

  defp session_attrs(opts) do
    authentication_method = Keyword.get(opts, :authentication_method)
    source_surface = Keyword.get(opts, :source_surface)
    trace_id = Keyword.get(opts, :trace_id)
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 8 * 60 * 60)
    enterprise_connection_id = Keyword.get(opts, :enterprise_connection_id)

    if present?(authentication_method) and present?(source_surface) and present?(trace_id) and
         is_integer(ttl_seconds) and ttl_seconds > 0 and
         valid_enterprise_connection?(authentication_method, enterprise_connection_id) do
      {:ok,
       %{
         authentication_method: authentication_method,
         enterprise_connection_id: enterprise_connection_id,
         source_surface: source_surface,
         trace_id: trace_id,
         ttl_seconds: ttl_seconds
       }}
    else
      {:error, :invalid_session_attributes}
    end
  end

  defp validate_workspace_scope(organization_id, workspace_id) do
    case Tenancy.validate_workspace_scope(organization_id, workspace_id) do
      :ok -> :ok
      {:error, :tenancy_storage_unavailable} -> {:error, :identity_storage_unavailable}
      _invalid_or_unavailable -> {:error, :invalid_scope}
    end
  end

  defp validate_session_record(%Session{purpose: @purpose, revoked_at: %DateTime{}} = session),
    do: {:reject, session, "session_revoked"}

  defp validate_session_record(
         %Session{
           purpose: @purpose,
           external_identity_link_id: external_identity_link_id,
           authentication_method: authentication_method,
           enterprise_connection_id: enterprise_connection_id,
           issued_at: %DateTime{} = issued_at,
           expires_at: %DateTime{} = expires_at,
           source_surface: source_surface,
           trace_id: trace_id,
           revoked_at: nil
         } = session
       ) do
    cond do
      not present?(external_identity_link_id) or not present?(authentication_method) or
        not present?(source_surface) or not present?(trace_id) or
        not valid_enterprise_connection?(authentication_method, enterprise_connection_id) or
          DateTime.compare(expires_at, issued_at) != :gt ->
        {:reject, session, "invalid_session"}

      DateTime.compare(expires_at, DateTime.utc_now()) != :gt ->
        {:reject, session, "session_expired"}

      true ->
        :ok
    end
  end

  defp validate_session_record(%Session{purpose: @purpose} = session),
    do: {:reject, session, "invalid_session"}

  defp validate_session_record(_session), do: {:error, :invalid_session}

  defp validate_principal(
         {:ok, %Principal{kind: "human", status: "active"} = principal},
         _session
       ),
       do: {:ok, principal}

  defp validate_principal({:ok, _inactive_or_missing}, session),
    do: {:reject, session, "principal_disabled"}

  defp validate_principal({:error, error}, _session), do: {:error, error}

  defp validate_external_identity_link(
         {:ok,
          %ExternalIdentityLink{
            principal_id: principal_id,
            status: "active",
            linking_state: "linked"
          } = external_identity_link},
         %Session{principal_id: principal_id}
       ),
       do: {:ok, external_identity_link}

  defp validate_external_identity_link({:ok, _inactive_or_missing}, %Session{} = session),
    do: {:reject, session, "identity_disabled"}

  defp validate_external_identity_link({:error, error}, _session), do: {:error, error}

  defp validate_resolved_scope(:ok, _session), do: :ok

  defp validate_resolved_scope({:error, :identity_storage_unavailable} = error, _session),
    do: error

  defp validate_resolved_scope({:error, _invalid_scope}, session),
    do: {:reject, session, "invalid_scope"}

  defp reject_session(session, reason, opts), do: reject(context(session), reason, opts)

  defp context(session), do: context(session, nil, nil)

  defp context(session, principal, external_identity_link) do
    %SessionContext{
      principal_id: session.principal_id,
      session_id: session.id,
      organization_id: session.organization_id,
      workspace_id: session.workspace_id,
      external_identity_link_id: session.external_identity_link_id,
      enterprise_connection_id: session.enterprise_connection_id,
      authentication_method: session.authentication_method,
      authentication_basis:
        authentication_basis(session.authentication_method, principal, external_identity_link),
      capabilities: MapSet.new(),
      trusted?: false
    }
  end

  defp authentication_basis(
         "local_development",
         %Principal{} = principal,
         %ExternalIdentityLink{} = external_identity_link
       ) do
    %{
      provider: external_identity_link.provider,
      provider_tenant: external_identity_link.provider_tenant,
      subject: external_identity_link.subject,
      verified_email: external_identity_link.verified_email,
      principal_email: principal.email,
      principal_kind: principal.kind,
      principal_status: principal.status,
      link_status: external_identity_link.status,
      linking_state: external_identity_link.linking_state
    }
  end

  defp authentication_basis(_authentication_method, _principal, _external_identity_link),
    do: nil

  defp event_attrs(attrs) do
    attrs
    |> Map.new()
    |> Map.update(:reason, nil, &normalize_reason/1)
  end

  defp normalize_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(reason), do: reason

  defp normalize_issue_result(
         {:ok,
          %OfficeGraph.Identity.HumanSessionIssueResult{
            status: "issued",
            session: session
          }}
       ) do
    {:ok, %{session: session, session_context: context(session)}}
  end

  defp normalize_issue_result(
         {:ok,
          %OfficeGraph.Identity.HumanSessionIssueResult{
            status: "rejected",
            reason: reason
          }}
       ) do
    {:error, String.to_existing_atom(reason)}
  end

  defp normalize_issue_result({:error, _error}), do: {:error, :identity_storage_unavailable}

  defp normalize_revoke_result({:ok, result}) when result in ["revoked", "already_revoked"],
    do: :ok

  defp normalize_revoke_result({:ok, "invalid"}), do: {:error, :invalid_session}
  defp normalize_revoke_result({:error, _error}), do: {:error, :identity_storage_unavailable}

  defp normalize_reject_result({:ok, "rejected"}), do: {:error, :invalid_session}
  defp normalize_reject_result({:ok, "invalid"}), do: {:error, :invalid_session}
  defp normalize_reject_result({:error, _error}), do: {:error, :identity_storage_unavailable}

  defp with_storage_boundary(fun) do
    fun.()
  rescue
    _error in @storage_exceptions -> {:error, :identity_storage_unavailable}
  end

  defp valid_enterprise_connection?("workos_sso", connection_id), do: present?(connection_id)
  defp valid_enterprise_connection?(_authentication_method, nil), do: true
  defp valid_enterprise_connection?(_authentication_method, _connection_id), do: false

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
