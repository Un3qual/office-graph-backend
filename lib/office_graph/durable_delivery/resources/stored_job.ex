defmodule OfficeGraph.DurableDelivery.StoredJob do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.DurableDelivery.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "oban_jobs"
    repo OfficeGraph.Repo
    migrate? false
  end

  attributes do
    attribute :id, :integer,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: false

    attribute :state, :string, allow_nil?: false, public?: true, writable?: false
    attribute :queue, :string, allow_nil?: false, public?: true, writable?: false
    attribute :worker, :string, allow_nil?: false, public?: true, writable?: false
    attribute :args, :map, allow_nil?: false, public?: true, writable?: false
    attribute :meta, :map, allow_nil?: false, public?: true, writable?: false
    attribute :attempt, :integer, allow_nil?: false, public?: true, writable?: false
    attribute :max_attempts, :integer, allow_nil?: false, public?: true, writable?: false
    attribute :attempted_at, :utc_datetime_usec, public?: true, writable?: false
    attribute :cancelled_at, :utc_datetime_usec, public?: true, writable?: false
    attribute :discarded_at, :utc_datetime_usec, public?: true, writable?: false
    attribute :inserted_at, :utc_datetime_usec, allow_nil?: false, public?: true, writable?: false
  end

  calculations do
    calculate :terminal_at,
              :utc_datetime_usec,
              expr(
                cond do
                  not is_nil(cancelled_at) -> cancelled_at
                  not is_nil(discarded_at) -> discarded_at
                  not is_nil(attempted_at) -> attempted_at
                  true -> inserted_at
                end
              )
  end

  actions do
    read :read do
      primary? true
      public? false
    end
  end
end
