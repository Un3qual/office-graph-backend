defmodule OfficeGraph.Identity.Principal do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "principals" do
    field :email, :string
    field :kind, :string
    field :status, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(principal, attrs) do
    principal
    |> cast(attrs, [:email, :kind, :status])
    |> validate_required([:email, :kind, :status])
    |> unique_constraint(:email)
  end
end
