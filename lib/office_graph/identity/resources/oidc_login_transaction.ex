defmodule OfficeGraph.Identity.Actions.StoreOidcLoginTransaction do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.OidcLoginTransaction

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    now = DateTime.utc_now()

    with :ok <- destroy_expired(now),
         {:ok, transaction, _notifications} <-
           Ash.create(
             OidcLoginTransaction,
             %{expires_at: input.arguments.expires_at},
             action: :create,
             authorize?: false,
             return_notifications?: true
           ) do
      {:ok, transaction}
    end
  end

  defp destroy_expired(now) do
    OidcLoginTransaction
    |> Ash.Query.filter(expires_at < ^now)
    |> Ash.bulk_destroy(:destroy, %{},
      authorize?: false,
      return_errors?: true,
      strategy: [:atomic]
    )
    |> case do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> {:error, Ash.Error.to_error_class(errors)}
    end
  end
end

defmodule OfficeGraph.Identity.Actions.ConsumeOidcLoginTransaction do
  @moduledoc false

  use Ash.Resource.Actions.Implementation

  alias OfficeGraph.Identity.OidcLoginTransaction

  require Ash.Query

  @impl true
  def run(input, _opts, _context) do
    OidcLoginTransaction
    |> Ash.Query.filter(id == ^input.arguments.id)
    |> Ash.Query.lock(:for_update)
    |> Ash.read_one(authorize?: false)
    |> case do
      {:ok, nil} ->
        {:ok, false}

      {:ok, transaction} ->
        valid? = DateTime.compare(transaction.expires_at, DateTime.utc_now()) != :lt

        case Ash.destroy(transaction,
               action: :destroy,
               authorize?: false,
               return_destroyed?: true,
               return_notifications?: true
             ) do
          {:ok, _destroyed, _notifications} -> {:ok, valid?}
          {:error, error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end

defmodule OfficeGraph.Identity.OidcLoginTransaction do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Identity.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "oidc_login_transactions"
    repo OfficeGraph.Repo
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

    destroy :destroy do
      primary? true
      public? false
    end

    action :store_login_transaction, :struct do
      public? false
      transaction? true
      constraints instance_of: __MODULE__

      argument :expires_at, :utc_datetime_usec, allow_nil?: false

      run OfficeGraph.Identity.Actions.StoreOidcLoginTransaction
    end

    action :consume_login_transaction, :boolean do
      public? false
      transaction? true

      argument :id, :uuid, allow_nil?: false

      run OfficeGraph.Identity.Actions.ConsumeOidcLoginTransaction
    end
  end
end
