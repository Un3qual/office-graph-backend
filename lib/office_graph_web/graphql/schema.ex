defmodule OfficeGraphWeb.GraphQL.Schema do
  use Absinthe.Schema

  import_types(OfficeGraphWeb.GraphQL.Common.Queries)
  import_types(OfficeGraphWeb.GraphQL.Compatibility.Types)
  import_types(OfficeGraphWeb.GraphQL.Compatibility.Mutations)
  import_types(OfficeGraphWeb.GraphQL.OperatorWorkflow.Types)
  import_types(OfficeGraphWeb.GraphQL.OperatorWorkflow.Queries)
  import_types(OfficeGraphWeb.GraphQL.PacketRunVerification.Types)
  import_types(OfficeGraphWeb.GraphQL.PacketRunVerification.Mutations)

  query do
    import_fields(:common_queries)
    import_fields(:operator_workflow_queries)
  end

  mutation do
    import_fields(:compatibility_mutations)
    import_fields(:packet_run_verification_mutations)
  end
end
