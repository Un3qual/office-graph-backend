defmodule OfficeGraph.Identity.HumanSessions do
  @moduledoc false

  alias OfficeGraph.Identity.{
    AuthenticationEvent,
    ExternalIdentityLink,
    Principal,
    Session,
    SessionContext
  }

  alias OfficeGraph.{Repo, Tenancy}

  require Ash.Query

  @purpose "human_web"

  @storage_exceptions [
    Ash.Error.Forbidden,
    Ash.Error.Framework,
    Ash.Error.Invalid,
    Ash.Error.Unknown,
    DBConnection.ConnectionError,
    Ecto.ConstraintError,
    Ecto.StaleEntryError,
    Postgrex.Error,
    RuntimeError
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
        Repo.transaction(fn ->
          lock_context!(principal.id, organization_id, workspace_id)

          with :ok <- validate_current_identity(principal.id, external_identity_link.id) do
            create_session(
              principal,
              external_identity_link,
              organization_id,
              workspace_id,
              attrs
            )
          end
        end)
      end)
    end
  end

  def issue(_principal, _link, _scope, _opts), do: {:error, :invalid_identity}

  def resolve(session_id) when is_binary(session_id) do
    with {:ok, %Session{} = session} <-
           Ash.get(Session, session_id, authorize?: false, not_found_error?: false),
         true <- valid_record?(session),
         {:ok, %Principal{kind: "human", status: "active"}} <-
           Ash.get(Principal, session.principal_id,
             authorize?: false,
             not_found_error?: false
           ),
         {:ok,
          %ExternalIdentityLink{
            principal_id: principal_id,
            status: "active",
            linking_state: "linked"
          }} <-
           Ash.get(ExternalIdentityLink, session.external_identity_link_id,
             authorize?: false,
             not_found_error?: false
           ),
         true <- principal_id == session.principal_id,
         :ok <- validate_workspace_scope(session.organization_id, session.workspace_id) do
      {:ok, context(session)}
    else
      _invalid_or_unavailable -> {:error, :invalid_session}
    end
  end

  def resolve(_session_id), do: {:error, :invalid_session}

  def revoke(session_id, opts) when is_binary(session_id) and is_list(opts) do
    trace_id = Keyword.get(opts, :trace_id)

    if present?(trace_id) do
      with_storage_boundary(fn ->
        Repo.transaction(fn ->
          lock_session_id!(session_id)

          case Ash.get(Session, session_id,
                 authorize?: false,
                 not_found_error?: false
               ) do
            {:ok, %Session{purpose: @purpose, revoked_at: nil} = session} ->
              session
              |> Ash.Changeset.for_update(:revoke, %{revoked_at: DateTime.utc_now()})
              |> Repo.ash_update!()

              create_event!(%{
                principal_id: session.principal_id,
                external_identity_link_id: session.external_identity_link_id,
                session_id: session.id,
                organization_id: session.organization_id,
                workspace_id: session.workspace_id,
                event: "logout",
                result: "succeeded",
                authentication_method: session.authentication_method,
                source_surface: session.source_surface,
                trace_id: trace_id
              })

              :ok

            {:ok, %Session{purpose: @purpose}} ->
              :ok

            _missing_or_wrong_purpose ->
              {:error, :invalid_session}
          end
        end)
      end)
    else
      {:error, :invalid_trace}
    end
  end

  def revoke(_session_id, _opts), do: {:error, :invalid_session}

  def record_event(attrs) when is_map(attrs) do
    with_storage_boundary(fn ->
      Repo.transaction(fn -> {:ok, create_event!(attrs)} end)
    end)
  end

  def record_event(_attrs), do: {:error, :invalid_authentication_event}

  defp session_attrs(opts) do
    authentication_method = Keyword.get(opts, :authentication_method)
    source_surface = Keyword.get(opts, :source_surface)
    trace_id = Keyword.get(opts, :trace_id)
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 8 * 60 * 60)

    if present?(authentication_method) and present?(source_surface) and present?(trace_id) and
         is_integer(ttl_seconds) and ttl_seconds > 0 do
      {:ok,
       %{
         authentication_method: authentication_method,
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
      _invalid_or_unavailable -> {:error, :invalid_scope}
    end
  end

  defp validate_current_identity(principal_id, external_identity_link_id) do
    principal =
      Principal
      |> Ash.Query.filter(id == ^principal_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one(authorize?: false)

    link =
      ExternalIdentityLink
      |> Ash.Query.filter(id == ^external_identity_link_id)
      |> Ash.Query.lock(:for_update)
      |> Ash.read_one(authorize?: false)

    case {principal, link} do
      {{:ok, %Principal{kind: "human", status: "active"}},
       {:ok,
        %ExternalIdentityLink{
          principal_id: ^principal_id,
          status: "active",
          linking_state: "linked"
        }}} ->
        :ok

      {{:ok, %Principal{kind: "human", status: "active"}}, {:ok, _inactive_or_missing_link}} ->
        {:error, :identity_disabled}

      {{:ok, %Principal{}}, _link} ->
        {:error, :principal_disabled}

      {{:ok, nil}, _link} ->
        {:error, :principal_disabled}

      {{:error, error}, _link} ->
        raise error

      {_principal, {:error, error}} ->
        raise error

      {_active_principal, {:ok, _inactive_or_missing_link}} ->
        {:error, :identity_disabled}
    end
  end

  defp create_session(principal, external_identity_link, organization_id, workspace_id, attrs) do
    now = DateTime.utc_now()

    revoke_active!(principal.id, organization_id, workspace_id, now)

    session =
      Repo.ash_create!(
        Session,
        %{
          id: Ecto.UUID.generate(),
          principal_id: principal.id,
          external_identity_link_id: external_identity_link.id,
          organization_id: organization_id,
          workspace_id: workspace_id,
          purpose: @purpose,
          authentication_method: attrs.authentication_method,
          issued_at: now,
          expires_at: DateTime.add(now, attrs.ttl_seconds, :second),
          source_surface: attrs.source_surface,
          trace_id: attrs.trace_id
        }
      )

    create_event!(%{
      principal_id: principal.id,
      external_identity_link_id: external_identity_link.id,
      session_id: session.id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      event: "login",
      result: "succeeded",
      authentication_method: attrs.authentication_method,
      source_surface: attrs.source_surface,
      trace_id: attrs.trace_id
    })

    {:ok, %{session: session, session_context: context(session)}}
  end

  defp revoke_active!(principal_id, organization_id, workspace_id, revoked_at) do
    Session
    |> Ash.Query.filter(
      principal_id == ^principal_id and organization_id == ^organization_id and
        workspace_id == ^workspace_id and purpose == ^@purpose and is_nil(revoked_at)
    )
    |> Ash.Query.lock(:for_update)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn session ->
      session
      |> Ash.Changeset.for_update(:revoke, %{revoked_at: revoked_at})
      |> Repo.ash_update!()
    end)
  end

  defp valid_record?(%Session{
         purpose: @purpose,
         external_identity_link_id: external_identity_link_id,
         authentication_method: authentication_method,
         issued_at: %DateTime{} = issued_at,
         expires_at: %DateTime{} = expires_at,
         source_surface: source_surface,
         trace_id: trace_id,
         revoked_at: nil
       }) do
    present?(external_identity_link_id) and present?(authentication_method) and
      present?(source_surface) and present?(trace_id) and
      DateTime.compare(expires_at, issued_at) == :gt and
      DateTime.compare(expires_at, DateTime.utc_now()) == :gt
  end

  defp valid_record?(_session), do: false

  defp context(session) do
    %SessionContext{
      principal_id: session.principal_id,
      session_id: session.id,
      organization_id: session.organization_id,
      workspace_id: session.workspace_id,
      external_identity_link_id: session.external_identity_link_id,
      authentication_method: session.authentication_method,
      capabilities: MapSet.new(),
      trusted?: false
    }
  end

  defp create_event!(attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put_new(:id, Ecto.UUID.generate())
      |> Map.update(:reason, nil, &normalize_reason/1)

    Repo.ash_create!(AuthenticationEvent, attrs)
  end

  defp normalize_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(reason), do: reason

  defp lock_context!(principal_id, organization_id, workspace_id) do
    lock!("human-session:#{principal_id}:#{organization_id}:#{workspace_id}:#{@purpose}")
  end

  defp lock_session_id!(session_id), do: lock!("human-session-id:#{session_id}")

  defp lock!(key) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [key])
  end

  defp with_storage_boundary(fun) do
    case fun.() do
      {:ok, result} -> result
      {:error, _storage_error} -> {:error, :identity_storage_unavailable}
      result -> result
    end
  rescue
    _error in @storage_exceptions -> {:error, :identity_storage_unavailable}
  catch
    _kind, _reason -> {:error, :identity_storage_unavailable}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
