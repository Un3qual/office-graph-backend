defmodule OfficeGraph.ProposedChanges.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.ProposedChanges.ProposedGraphChange,
          :get_proposed_graph_change,
          :read

      list OfficeGraph.ProposedChanges.ProposedGraphChange,
           :list_proposed_graph_changes,
           :read,
           relay?: true
    end

    mutations do
      action OfficeGraph.ProposedChanges.ProposedGraphChange,
             :apply_proposed_changes,
             :apply_proposed_changes do
        relay_id_translations(
          input: [
            normalized_event_id: :normalized_intake_event,
            proposed_change_ids: :proposed_graph_change
          ]
        )
      end
    end
  end

  json_api do
    routes do
      base_route "/proposed-graph-changes",
                 OfficeGraph.ProposedChanges.ProposedGraphChange do
        get(:read, primary?: true)
        index :read
      end

      route(
        OfficeGraph.ProposedChanges.ProposedGraphChange,
        :post,
        "/commands/apply-proposed-changes",
        :apply_proposed_changes
      )
    end
  end

  resources do
    resource OfficeGraph.ProposedChanges.ProposedGraphChange
  end
end
