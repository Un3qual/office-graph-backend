defmodule OfficeGraph.Integrations.Domain do
  @moduledoc false

  use Ash.Domain,
    extensions: [AshGraphql.Domain, AshJsonApi.Domain],
    otp_app: :office_graph

  graphql do
    queries do
      get OfficeGraph.Integrations.NormalizedIntakeEvent,
          :get_normalized_intake_event,
          :read

      list OfficeGraph.Integrations.NormalizedIntakeEvent,
           :list_normalized_intake_events,
           :read,
           relay?: true
    end

    mutations do
      action OfficeGraph.Integrations.NormalizedIntakeEvent,
             :submit_manual_intake,
             :submit_manual_intake
    end
  end

  json_api do
    routes do
      base_route "/normalized-intake-events",
                 OfficeGraph.Integrations.NormalizedIntakeEvent do
        get(:read, primary?: true)
        index :read
        related(:proposed_changes, :read)
      end

      route(
        OfficeGraph.Integrations.NormalizedIntakeEvent,
        :post,
        "/commands/submit-manual-intake",
        :submit_manual_intake
      )
    end
  end

  resources do
    resource OfficeGraph.Integrations.ExternalSource
    resource OfficeGraph.Integrations.RawArchive
    resource OfficeGraph.Integrations.NormalizedIntakeEvent
    resource OfficeGraph.Integrations.IntegrationCredential
  end
end
