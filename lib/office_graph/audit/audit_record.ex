defmodule OfficeGraph.Audit.AuditRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_records" do
    field :operation_id, :binary_id
    field :actor_principal_id, :binary_id
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :sensitive, :boolean, default: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [
      :operation_id,
      :actor_principal_id,
      :action,
      :resource_type,
      :resource_id,
      :sensitive
    ])
    |> validate_required([
      :operation_id,
      :actor_principal_id,
      :action,
      :resource_type,
      :resource_id,
      :sensitive
    ])
    |> foreign_key_constraint(:operation_id)
    |> foreign_key_constraint(:actor_principal_id)
  end
end
