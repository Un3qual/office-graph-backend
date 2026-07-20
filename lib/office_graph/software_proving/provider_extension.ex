defmodule OfficeGraph.SoftwareProving.ProviderExtension do
  @moduledoc false

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)
    accept = Keyword.fetch!(opts, :accept)

    quote do
      use Ash.Resource,
        domain: OfficeGraph.SoftwareProving.Domain,
        data_layer: AshPostgres.DataLayer

      postgres do
        table unquote(table)
        repo OfficeGraph.Repo
        migrate? false

        identity_index_names unique_workspace_node_id:
                               unquote("#{table}_workspace_node_id_index"),
                             unique_organization_node_id:
                               unquote("#{table}_organization_node_id_index")
      end

      actions do
        read :read do
          primary? true
          public? false
        end

        create :create do
          accept unquote(accept)
          public? false
        end
      end
    end
  end
end
