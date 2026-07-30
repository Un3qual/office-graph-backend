defmodule OfficeGraph.Identity.LocalDevelopmentIdentity do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :principal, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Identity.Principal]

    field :profile, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Identity.PrincipalProfile]

    field :external_identity_link, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Identity.ExternalIdentityLink]
  end

  def from_records(principal, profile, external_identity_link) do
    new(
      principal: principal,
      profile: profile,
      external_identity_link: external_identity_link
    )
  end
end

defmodule OfficeGraph.Identity.Actions.EnsureLocalDevelopmentIdentity do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.{
    ExternalIdentityLink,
    LocalDevelopmentIdentity,
    Principal,
    PrincipalProfile
  }

  @impl true
  def run(input, _opts, _context) do
    attrs = input.arguments
    now = DateTime.utc_now()

    with {:ok, principal} <-
           ensure(Principal, %{
             email: attrs.email,
             kind: "human",
             status: attrs.principal_status
           }),
         {:ok, profile} <-
           ensure(PrincipalProfile, %{
             principal_id: principal.id,
             display_name: attrs.display_name
           }),
         {:ok, external_identity_link} <-
           ensure(ExternalIdentityLink, %{
             principal_id: principal.id,
             provider: attrs.provider,
             provider_tenant: attrs.provider_tenant,
             subject: attrs.subject,
             verified_email: attrs.email,
             status: attrs.link_status,
             linking_state: "linked",
             first_linked_at: now,
             disabled_at: disabled_at(attrs.link_status, now)
           }) do
      LocalDevelopmentIdentity.from_records(principal, profile, external_identity_link)
    end
  end

  defp disabled_at("disabled", now), do: now
  defp disabled_at(_status, _now), do: nil

  defp ensure(ExternalIdentityLink, attrs) do
    ExternalIdentityLink
    |> Ash.Changeset.for_create(:ensure_local_development, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp ensure(resource, attrs) do
    resource
    |> Ash.Changeset.for_create(:ensure, attrs)
    |> Ash.create(authorize?: false, return_notifications?: true)
    |> consume_notifications()
  end

  defp consume_notifications({:ok, record, _notifications}), do: {:ok, record}
  defp consume_notifications({:error, error}), do: {:error, error}
end
