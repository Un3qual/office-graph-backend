defmodule OfficeGraphWeb.GraphQL.Common.Queries do
  use Absinthe.Schema.Notation

  object :common_queries do
    field :health, non_null(:string) do
      resolve(fn _, _ -> {:ok, "ok"} end)
    end
  end
end
