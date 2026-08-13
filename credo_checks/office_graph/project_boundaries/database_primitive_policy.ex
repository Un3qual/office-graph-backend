defmodule OfficeGraph.ProjectQuality.DatabasePrimitivePolicy do
  @moduledoc false

  @repo_raw_sql MapSet.new([:query, :query!, :query_many, :query_many!])
  @repo_direct MapSet.new([
                 :aggregate,
                 :all,
                 :all_by,
                 :checked_out?,
                 :checkout,
                 :delete,
                 :delete!,
                 :delete_all,
                 :disconnect_all,
                 :explain,
                 :exists?,
                 :get,
                 :get!,
                 :get_by,
                 :get_by!,
                 :get_dynamic_repo,
                 :in_transaction?,
                 :insert,
                 :insert!,
                 :insert_all,
                 :insert_or_update,
                 :insert_or_update!,
                 :load,
                 :one,
                 :one!,
                 :preload,
                 :preload!,
                 :put_dynamic_repo,
                 :reload,
                 :reload!,
                 :rollback,
                 :start_link,
                 :stop,
                 :stream,
                 :transact,
                 :transaction,
                 :update,
                 :update!,
                 :update_all
               ])
  @ecto_sql_raw MapSet.new([
                  :execute,
                  :execute_ddl,
                  :into,
                  :query,
                  :query!,
                  :query_many,
                  :query_many!,
                  :reduce,
                  :stream
                ])
  @ecto_sql_direct MapSet.new([
                     :checked_out?,
                     :checkout,
                     :disconnect_all,
                     :explain,
                     :in_transaction?,
                     :insert_all,
                     :rollback,
                     :table_exists?,
                     :to_sql,
                     :transaction
                   ])
  @postgrex_raw MapSet.new([
                  :execute,
                  :execute!,
                  :prepare,
                  :prepare!,
                  :prepare_execute,
                  :prepare_execute!,
                  :query,
                  :query!,
                  :stream
                ])
  @postgrex_direct MapSet.new([
                     :call,
                     :child_spec,
                     :close,
                     :close!,
                     :listen,
                     :listen!,
                     :parameters,
                     :rollback,
                     :start_link,
                     :transaction,
                     :unlisten,
                     :unlisten!
                   ])
  @postgrex_modules MapSet.new([
                      "Postgrex",
                      "Postgrex.Notifications",
                      "Postgrex.ReplicationConnection",
                      "Postgrex.SimpleConnection"
                    ])
  @db_connection_raw MapSet.new([
                       :execute,
                       :execute!,
                       :prepare,
                       :prepare!,
                       :prepare_execute,
                       :prepare_execute!,
                       :prepare_stream,
                       :reduce,
                       :stream
                     ])
  @db_connection_direct MapSet.new([
                          :child_spec,
                          :close,
                          :close!,
                          :disconnect_all,
                          :get_connection_metrics,
                          :rollback,
                          :run,
                          :start_link,
                          :status,
                          :transaction
                        ])
  @postgres_connection_raw MapSet.new([:execute, :execute_ddl, :prepare_execute, :query])
  @postgres_adapter_direct MapSet.new([
                             :execute,
                             :lock_for_migrations,
                             :storage_down,
                             :storage_status,
                             :storage_up,
                             :structure_dump,
                             :structure_load
                           ])
  @ecto_migrator_direct MapSet.new([
                          :down,
                          :migrated_versions,
                          :migrations,
                          :run,
                          :start_link,
                          :up,
                          :with_repo
                        ])
  @multi_direct MapSet.new([
                  :all,
                  :append,
                  :delete,
                  :delete_all,
                  :error,
                  :exists?,
                  :insert,
                  :insert_all,
                  :insert_or_update,
                  :merge,
                  :one,
                  :prepend,
                  :put,
                  :run,
                  :update,
                  :update_all
                ])
  @private_direct_modules MapSet.new([
                            "DBConnection.Holder",
                            "Ecto.Migration.Runner",
                            "Ecto.Repo.Queryable",
                            "Ecto.Repo.Registry",
                            "Ecto.Repo.Schema",
                            "Ecto.Repo.Supervisor",
                            "Ecto.Repo.Transaction"
                          ])

  @spec classify(String.t(), atom()) :: :raw_sql | :direct_ecto | nil
  def classify(module, operation) do
    cond do
      module == "OfficeGraph.Repo" and MapSet.member?(@repo_raw_sql, operation) ->
        :raw_sql

      module == "OfficeGraph.Repo" and MapSet.member?(@repo_direct, operation) ->
        :direct_ecto

      module == "Ecto.Adapters.SQL" and MapSet.member?(@ecto_sql_raw, operation) ->
        :raw_sql

      module == "Ecto.Adapters.SQL" and MapSet.member?(@ecto_sql_direct, operation) ->
        :direct_ecto

      module == "Ecto.Adapters.Postgres.Connection" and
          MapSet.member?(@postgres_connection_raw, operation) ->
        :raw_sql

      MapSet.member?(@postgrex_modules, module) and
          MapSet.member?(@postgrex_raw, operation) ->
        :raw_sql

      MapSet.member?(@postgrex_modules, module) and
          MapSet.member?(@postgrex_direct, operation) ->
        :direct_ecto

      module == "DBConnection" and MapSet.member?(@db_connection_raw, operation) ->
        :raw_sql

      module == "DBConnection" and MapSet.member?(@db_connection_direct, operation) ->
        :direct_ecto

      module == "Ecto.Adapters.Postgres" and
          MapSet.member?(@postgres_adapter_direct, operation) ->
        :direct_ecto

      module == "Ecto.Migrator" and MapSet.member?(@ecto_migrator_direct, operation) ->
        :direct_ecto

      module == "Ecto.Multi" and MapSet.member?(@multi_direct, operation) ->
        :direct_ecto

      MapSet.member?(@private_direct_modules, module) ->
        :direct_ecto

      true ->
        nil
    end
  end

  @spec low_level_module?(String.t()) :: boolean()
  def low_level_module?(module) do
    module in [
      "DBConnection",
      "Ecto.Adapters.Postgres",
      "Ecto.Adapters.Postgres.Connection",
      "Ecto.Adapters.SQL",
      "Ecto.Migration",
      "Ecto.Migrator",
      "Ecto.Multi",
      "OfficeGraph.Repo"
    ] or MapSet.member?(@postgrex_modules, module) or
      MapSet.member?(@private_direct_modules, module)
  end

  @spec construct(String.t(), atom()) :: String.t()
  def construct("OfficeGraph.Repo", operation), do: "Repo.#{operation}"
  def construct(module, operation), do: "#{module}.#{operation}"
end
