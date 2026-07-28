defmodule OfficeGraph.Identity.OidcLoginTransaction do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "oidc_login_transactions"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :expires_at, :utc_datetime_usec, allow_nil?: false, public?: true

    create_timestamp :inserted_at, public?: true
  end

  actions do
    read :read do
      primary? true
      public? false
    end

    create :create do
      accept [:id, :expires_at]
    end
  end
end
