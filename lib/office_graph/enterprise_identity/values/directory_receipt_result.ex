defmodule OfficeGraph.EnterpriseIdentity.DirectoryReceiptResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:created, :replayed]]

    field :sync_event, :struct,
      allow_nil?: false,
      constraints: [instance_of: OfficeGraph.EnterpriseIdentity.DirectorySyncEvent]
  end

  def created(sync_event), do: new(status: :created, sync_event: sync_event)
  def replayed(sync_event), do: new(status: :replayed, sync_event: sync_event)
end

defmodule OfficeGraph.EnterpriseIdentity.DirectoryProcessingResult do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:applied, :stale, :review_required, :already_processed]]
  end

  def completed(status), do: new(status: status)
end
