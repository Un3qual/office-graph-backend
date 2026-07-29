defmodule OfficeGraph.Integrations.CommandResults.SubmitManualIntake do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :command, :string, allow_nil?: false
    field :operation_id, :uuid, allow_nil?: false
    field :affected_ids, {:array, OfficeGraph.CommandSupport.TypedId}, allow_nil?: false

    field :normalized_event, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.Integrations.NormalizedIntakeEvent]

    field :proposed_changes, {:array, :struct},
      allow_nil?: false,
      constraints: [items: [instance_of: OfficeGraph.ProposedChanges.ProposedGraphChange]]
  end

  use AshGraphql.Type

  @impl true
  def graphql_type(_constraints), do: :submit_manual_intake_payload
end

defimpl Jason.Encoder, for: OfficeGraph.Integrations.CommandResults.SubmitManualIntake do
  def encode(result, options) do
    Jason.Encode.map(
      %{
        command: result.command,
        operation_id: result.operation_id,
        affected_ids: result.affected_ids,
        normalized_event: %{id: result.normalized_event.id},
        proposed_changes: Enum.map(result.proposed_changes, &%{id: &1.id})
      },
      options
    )
  end
end

defmodule OfficeGraph.Integrations.NormalizedIntakeEvent do
  @moduledoc false

  use Ash.Resource,
    domain: OfficeGraph.Integrations.Domain,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshGraphql.Resource, AshJsonApi.Resource]

  postgres do
    table "normalized_intake_events"
    repo OfficeGraph.Repo
    migrate? false

    foreign_key_names organization_id: "normalized_intake_events_organization_id_fkey",
                      workspace_id: "normalized_intake_events_workspace_id_fkey",
                      raw_archive_id: "normalized_intake_events_raw_archive_id_fkey",
                      operation_id: "normalized_intake_events_operation_id_fkey",
                      duplicate_of_id: "normalized_intake_events_duplicate_of_id_fkey"
  end

  attributes do
    attribute :id, :uuid,
      primary_key?: true,
      allow_nil?: false,
      public?: true,
      writable?: true,
      generated?: true

    attribute :source_identity, :string, allow_nil?: false, public?: true
    attribute :replay_identity, :string, allow_nil?: false, public?: true
    attribute :outcome, :string, allow_nil?: false, public?: true
    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at, public?: true
  end

  relationships do
    belongs_to :duplicate_of, OfficeGraph.Integrations.NormalizedIntakeEvent do
      source_attribute :duplicate_of_id
      destination_attribute :id
      attribute_public? true
    end

    belongs_to :operation, OfficeGraph.Operations.OperationCorrelation do
      source_attribute :operation_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :organization, OfficeGraph.Tenancy.Organization do
      source_attribute :organization_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :raw_archive, OfficeGraph.Integrations.RawArchive do
      source_attribute :raw_archive_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    belongs_to :workspace, OfficeGraph.Tenancy.Workspace do
      source_attribute :workspace_id
      destination_attribute :id
      allow_nil? false
      attribute_public? true
    end

    has_many :duplicate_events, OfficeGraph.Integrations.NormalizedIntakeEvent do
      source_attribute :id
      destination_attribute :duplicate_of_id
    end

    has_many :proposed_changes, OfficeGraph.ProposedChanges.ProposedGraphChange do
      source_attribute :id
      destination_attribute :normalized_event_id
      public? true
    end
  end

  actions do
    read :read do
      primary? true
      pagination keyset?: true, countable: false, required?: false
    end

    create :create do
      accept [
        :id,
        :organization_id,
        :workspace_id,
        :raw_archive_id,
        :operation_id,
        :source_identity,
        :replay_identity,
        :outcome,
        :duplicate_of_id
      ]
    end

    action :submit_manual_intake,
           OfficeGraph.Integrations.CommandResults.SubmitManualIntake do
      argument :idempotency_key, :string, allow_nil?: false
      argument :source_identity, :string, allow_nil?: false
      argument :replay_identity, :string, allow_nil?: false

      argument :body, :string,
        allow_nil?: false,
        constraints: [trim?: false, match: ~r/\S/]

      run fn input, context ->
        OfficeGraph.Integrations.Actions.SubmitManualIntake.run(input, [], context)
      end
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability, capability: :skeleton_read}
    end

    policy action_type(:read) do
      authorize_if expr(
                     organization_id == ^actor(:organization_id) and
                       workspace_id == ^actor(:workspace_id)
                   )
    end

    policy action(:submit_manual_intake) do
      authorize_if {OfficeGraph.Authorization.Checks.HasCapability,
                    capability: :manual_intake_submit}
    end
  end

  identities do
    identity :accepted_replay_key,
             [:organization_id, :workspace_id, :source_identity, :replay_identity],
             where: expr(outcome == "accepted")
  end

  graphql do
    type :normalized_intake_event
    paginate_relationship_with(proposed_changes: :relay)
  end

  json_api do
    type "normalized-intake-event"
  end
end
