defmodule OfficeGraph.CommandSupport.TypedId do
  @moduledoc false

  @derive {Jason.Encoder, only: [:type, :id]}
  use Ash.TypedStruct

  typed_struct do
    field :type, :string, allow_nil?: false
    field :id, :uuid, allow_nil?: false
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :operator_typed_id
end
