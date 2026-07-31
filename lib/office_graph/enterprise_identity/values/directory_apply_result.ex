defmodule OfficeGraph.EnterpriseIdentity.DirectoryApplyResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:applied, :stale, :review_required]]

    field :resource, :struct, allow_nil?: false
  end

  def applied(resource), do: new(status: :applied, resource: resource)
  def stale(resource), do: new(status: :stale, resource: resource)
  def review_required(resource), do: new(status: :review_required, resource: resource)

  def to_public_result(%__MODULE__{status: status, resource: resource}),
    do: {:ok, %{status: status, resource: resource}}
end
