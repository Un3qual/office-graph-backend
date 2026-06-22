defmodule OfficeGraph.Content.Domain do
  @moduledoc false

  use Ash.Domain, otp_app: :office_graph

  resources do
    resource OfficeGraph.Content.Document
    resource OfficeGraph.Content.DocumentBlock
    resource OfficeGraph.Content.DocumentMark
    resource OfficeGraph.Content.DocumentReference
    resource OfficeGraph.Content.DocumentRevision
  end
end
