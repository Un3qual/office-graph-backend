defmodule OfficeGraph.SoftwareProving.Resource do
  @moduledoc false

  @common_accept [
    :id,
    :organization_id,
    :workspace_id,
    :source_id,
    :provider_version,
    :provider_sequence,
    :provider_updated_at,
    :sync_state,
    :lifecycle_state,
    :operation_id,
    :deleted_at
  ]

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    accept = @common_accept ++ Keyword.fetch!(opts, :accept)

    validations =
      for {attribute, values} <- Keyword.get(opts, :validations, []) do
        quote do
          validate one_of(unquote(attribute), unquote(values))
        end
      end

    quote do
      use Ash.Resource,
        domain: OfficeGraph.SoftwareProving.Domain,
        data_layer: AshPostgres.DataLayer,
        primary_read_warning?: false

      postgres do
        table unquote(table)
        repo OfficeGraph.Repo
        migrate? false
      end

      attributes do
        uuid_primary_key :id, writable?: true
        attribute :organization_id, :uuid, allow_nil?: false, public?: true
        attribute :workspace_id, :uuid, public?: true
        attribute :source_id, :uuid, public?: true
        attribute :provider_version, :string, public?: true
        attribute :provider_sequence, :integer, public?: true
        attribute :provider_updated_at, :utc_datetime_usec, public?: true

        attribute :sync_state, :string,
          allow_nil?: false,
          default: "native",
          public?: true

        attribute :lifecycle_state, :string,
          allow_nil?: false,
          default: "active",
          public?: true

        attribute :operation_id, :uuid, allow_nil?: false, public?: true
        attribute :deleted_at, :utc_datetime_usec, public?: true

        create_timestamp :inserted_at, public?: true
        update_timestamp :updated_at, public?: true
      end

      actions do
        read :read do
          primary? true
          public? false
          filter expr(is_nil(^Ash.Expr.ref(:deleted_at)))
        end

        read :read_with_deleted do
          public? false
        end

        create :create do
          accept unquote(accept)
          validate one_of(:sync_state, ~w(native pending synced stale failed))
          validate one_of(:lifecycle_state, ~w(active archived deleted))
          unquote_splicing(validations)
          public? false
        end

        update :reconcile do
          accept unquote(accept -- [:id, :organization_id, :workspace_id, :source_id])
          validate one_of(:sync_state, ~w(native pending synced stale failed))
          validate one_of(:lifecycle_state, ~w(active archived deleted))
          unquote_splicing(validations)
          require_atomic? false
          public? false
        end
      end

      relationships do
        belongs_to :organization, OfficeGraph.Tenancy.Organization do
          source_attribute :organization_id
          destination_attribute :id
          define_attribute? false
          public? true
        end

        belongs_to :governing_workspace, OfficeGraph.Tenancy.Workspace do
          source_attribute :workspace_id
          destination_attribute :id
          define_attribute? false
          public? true
        end

        belongs_to :external_source, OfficeGraph.Integrations.ExternalSource do
          source_attribute :source_id
          destination_attribute :id
          define_attribute? false
          public? true
        end

        belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
          source_attribute :operation_id
          destination_attribute :id
          define_attribute? false
          public? true
        end
      end
    end
  end
end
