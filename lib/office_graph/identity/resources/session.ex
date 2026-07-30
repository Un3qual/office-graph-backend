defmodule OfficeGraph.Identity.HumanSessionIssueResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :string, allow_nil?: false
    field :reason, :string

    field :session, :struct, constraints: [instance_of: OfficeGraph.Identity.Session]
  end

  def issued(session), do: new(status: "issued", session: session)
  def rejected(reason), do: new(status: "rejected", reason: Atom.to_string(reason))
end

defmodule OfficeGraph.Identity.Actions.IssueHumanSession do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.{
    AuthenticationEvent,
    ExternalIdentityLink,
    HumanSessionPersistence,
    HumanSessionIssueResult,
    Principal,
    Session
  }

  require Ash.Query

  @purpose "human_web"

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments

    case locked_identity(attrs.principal_id, attrs.external_identity_link_id) do
      {:ok, principal, external_identity_link} ->
        create_session(principal, external_identity_link, attrs)

      {:rejected, reason} ->
        HumanSessionIssueResult.rejected(reason)

      {:error, error} ->
        {:error, error}
    end
  end

  defp locked_identity(principal_id, external_identity_link_id) do
    with {:ok, principal} <- locked_principal(principal_id),
         {:ok, external_identity_link} <- locked_external_identity(external_identity_link_id) do
      classify_identity(principal, external_identity_link, principal_id)
    end
  end

  defp locked_principal(principal_id) do
    Principal
    |> Ash.Query.filter(id == ^principal_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp locked_external_identity(external_identity_link_id) do
    ExternalIdentityLink
    |> Ash.Query.filter(id == ^external_identity_link_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp classify_identity(
         %Principal{kind: "human", status: "active"} = principal,
         %ExternalIdentityLink{
           principal_id: principal_id,
           status: "active",
           linking_state: "linked"
         } = external_identity_link,
         principal_id
       ) do
    {:ok, principal, external_identity_link}
  end

  defp classify_identity(
         %Principal{kind: "human", status: "active"},
         _inactive_or_missing_link,
         _principal_id
       ) do
    {:rejected, :identity_disabled}
  end

  defp classify_identity(_inactive_or_missing_principal, _link, _principal_id) do
    {:rejected, :principal_disabled}
  end

  defp create_session(principal, external_identity_link, attrs) do
    now = DateTime.utc_now()

    with :ok <-
           revoke_active(
             principal.id,
             attrs.organization_id,
             attrs.workspace_id,
             now,
             attrs.trace_id
           ),
         {:ok, session} <-
           create(Session, %{
             principal_id: principal.id,
             external_identity_link_id: external_identity_link.id,
             organization_id: attrs.organization_id,
             workspace_id: attrs.workspace_id,
             purpose: @purpose,
             authentication_method: attrs.authentication_method,
             enterprise_connection_id: attrs.enterprise_connection_id,
             issued_at: now,
             expires_at: DateTime.add(now, attrs.ttl_seconds, :second),
             source_surface: attrs.source_surface,
             trace_id: attrs.trace_id
           }),
         {:ok, _event} <-
           create_event(%{
             principal_id: principal.id,
             external_identity_link_id: external_identity_link.id,
             session_id: session.id,
             organization_id: attrs.organization_id,
             workspace_id: attrs.workspace_id,
             event: "login",
             result: "succeeded",
             reason: "login_completed",
             authentication_method: attrs.authentication_method,
             source_surface: attrs.source_surface,
             trace_id: attrs.trace_id
           }) do
      HumanSessionIssueResult.issued(session)
    end
  end

  defp revoke_active(principal_id, organization_id, workspace_id, revoked_at, trace_id) do
    Session
    |> Ash.Query.filter(
      principal_id == ^principal_id and organization_id == ^organization_id and
        workspace_id == ^workspace_id and purpose == ^@purpose and is_nil(revoked_at)
    )
    |> Ash.Query.sort(id: :asc)
    |> Ash.Query.lock(:for_update)
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, sessions} ->
        Enum.reduce_while(sessions, :ok, fn session, :ok ->
          case revoke_session(session, revoked_at, trace_id) do
            :ok -> {:cont, :ok}
            {:error, error} -> {:halt, {:error, error}}
          end
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  defp revoke_session(session, revoked_at, trace_id) do
    with {:ok, revoked_session} <- update(session, :revoke, %{revoked_at: revoked_at}),
         {:ok, _event} <-
           create_event(%{
             principal_id: revoked_session.principal_id,
             external_identity_link_id: revoked_session.external_identity_link_id,
             session_id: revoked_session.id,
             organization_id: revoked_session.organization_id,
             workspace_id: revoked_session.workspace_id,
             event: "revocation",
             result: "succeeded",
             reason: "session_replaced",
             authentication_method: revoked_session.authentication_method,
             source_surface: revoked_session.source_surface,
             trace_id: trace_id
           }) do
      :ok
    end
  end

  defp create_event(attrs) do
    with :ok <- HumanSessionPersistence.before_access(:issue_event) do
      create(AuthenticationEvent, attrs)
    end
  end

  defp create(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp update(record, action, attrs) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end

defmodule OfficeGraph.Identity.Actions.RevokeHumanSession do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.{AuthenticationEvent, Session}

  require Ash.Query

  @purpose "human_web"

  @impl true
  def run(input, _opts, _context) do
    case locked_session(input.arguments.session_id) do
      {:ok, %Session{purpose: @purpose, revoked_at: nil} = session} ->
        revoke(session, input.arguments.trace_id)

      {:ok, %Session{purpose: @purpose}} ->
        {:ok, "already_revoked"}

      {:ok, _missing_or_wrong_purpose} ->
        {:ok, "invalid"}

      {:error, error} ->
        {:error, error}
    end
  end

  defp locked_session(session_id) do
    Session
    |> Ash.Query.filter(id == ^session_id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
  end

  defp revoke(session, trace_id) do
    with {:ok, revoked_session} <-
           update(session, :revoke, %{revoked_at: DateTime.utc_now()}),
         {:ok, _event} <-
           create_event(%{
             principal_id: revoked_session.principal_id,
             external_identity_link_id: revoked_session.external_identity_link_id,
             session_id: revoked_session.id,
             organization_id: revoked_session.organization_id,
             workspace_id: revoked_session.workspace_id,
             event: "logout",
             result: "succeeded",
             reason: "user_logout",
             authentication_method: revoked_session.authentication_method,
             source_surface: revoked_session.source_surface,
             trace_id: trace_id
           }) do
      {:ok, "revoked"}
    end
  end

  defp create_event(attrs) do
    AuthenticationEvent
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp update(record, action, attrs) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end

defmodule OfficeGraph.Identity.Session do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sessions"
    repo OfficeGraph.Repo

    identity_index_names unique_context:
                           "sessions_principal_id_organization_id_workspace_id_purpose_inde"

    references do
      reference :workspace do
        name "sessions_workspace_scope_fkey"
        match_with organization_id: :organization_id
      end
    end
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :purpose, :string, allow_nil?: false, public?: true
    attribute :authentication_method, :string, public?: true
    attribute :enterprise_connection_id, :uuid, public?: true
    attribute :issued_at, :utc_datetime_usec, public?: true
    attribute :expires_at, :utc_datetime_usec, public?: true
    attribute :source_surface, :string, public?: true
    attribute :trace_id, :string, public?: true
    attribute :revoked_at, :utc_datetime_usec, public?: true
    attribute :active_identity_slot, :string, public?: false, writable?: false

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :external_identity_link, OfficeGraph.Identity.ExternalIdentityLink do
      source_attribute :external_identity_link_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :principal, OfficeGraph.Identity.Principal do
      source_attribute :principal_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :id,
        :principal_id,
        :external_identity_link_id,
        :organization_id,
        :workspace_id,
        :purpose,
        :authentication_method,
        :enterprise_connection_id,
        :issued_at,
        :expires_at,
        :source_surface,
        :trace_id,
        :revoked_at
      ]

      change set_attribute(:active_identity_slot, nil)

      change set_attribute(:active_identity_slot, "active") do
        where attribute_equals(:revoked_at, nil)
      end
    end

    create :ensure_local_owner do
      public? false
      accept [:principal_id, :organization_id, :workspace_id, :purpose]
      upsert? true
      upsert_identity :unique_context
      upsert_fields []
      return_skipped_upsert? true
      change set_attribute(:active_identity_slot, "active")
    end

    update :revoke do
      accept [:revoked_at]
      change set_attribute(:active_identity_slot, nil)
    end

    action :issue_human_session, OfficeGraph.Identity.HumanSessionIssueResult do
      public? false
      transaction? true

      touches_resources [
        OfficeGraph.Identity.AuthenticationEvent,
        OfficeGraph.Identity.ExternalIdentityLink,
        OfficeGraph.Identity.Principal
      ]

      argument :principal_id, :uuid, allow_nil?: false
      argument :external_identity_link_id, :uuid, allow_nil?: false
      argument :organization_id, :uuid, allow_nil?: false
      argument :workspace_id, :uuid, allow_nil?: false
      argument :authentication_method, :string, allow_nil?: false
      argument :enterprise_connection_id, :uuid
      argument :source_surface, :string, allow_nil?: false
      argument :trace_id, :string, allow_nil?: false
      argument :ttl_seconds, :integer, allow_nil?: false, constraints: [min: 1]

      run OfficeGraph.Identity.Actions.IssueHumanSession
    end

    action :revoke_human_session, :string do
      public? false
      transaction? true
      touches_resources [OfficeGraph.Identity.AuthenticationEvent]

      argument :session_id, :uuid, allow_nil?: false
      argument :trace_id, :string, allow_nil?: false

      run OfficeGraph.Identity.Actions.RevokeHumanSession
    end
  end

  identities do
    identity :unique_context,
             [
               :principal_id,
               :organization_id,
               :workspace_id,
               :purpose,
               :active_identity_slot
             ]
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(
                     principal_id == ^actor(:principal_id) and
                       organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end
  end
end
