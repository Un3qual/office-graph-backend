defmodule OfficeGraph.Authorization.AuthorizationDecision do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "authorization_decisions" do
    field :operation_id, :binary_id
    field :principal_id, :binary_id
    field :organization_id, :binary_id
    field :action, :string
    field :decision, :string
    field :reason, :string

    timestamps(type: :utc_datetime_usec)
  end
end
