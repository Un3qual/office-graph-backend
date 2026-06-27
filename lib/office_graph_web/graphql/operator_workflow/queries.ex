defmodule OfficeGraphWeb.GraphQL.OperatorWorkflow.Queries do
  use Absinthe.Schema.Notation

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.GraphQL.Common.Errors

  object :operator_workflow_queries do
    field :operator_inbox, non_null(:operator_inbox) do
      resolve(fn _, _ ->
        case ApiSupport.read_operator_inbox() do
          {:ok, inbox} -> {:ok, inbox}
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_workflow_item, non_null(:operator_workflow_item) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, _ ->
        case ApiSupport.read_operator_workflow_item(%{normalized_event_id: id}) do
          {:ok, item} -> {:ok, item}
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_packet_readiness, non_null(:operator_packet_readiness) do
      arg(:input, non_null(:operator_packet_readiness_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.read_operator_packet_readiness(input) do
          {:ok, readiness} -> {:ok, readiness}
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_run_state, non_null(:operator_run_state) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, _ ->
        case ApiSupport.read_operator_run_state(%{run_id: id}) do
          {:ok, run_state} -> {:ok, run_state}
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :operator_verification_outcome, non_null(:operator_verification_outcome) do
      arg(:id, non_null(:id))

      resolve(fn %{id: id}, _ ->
        case ApiSupport.read_operator_verification_outcome(%{run_id: id}) do
          {:ok, outcome} -> {:ok, outcome}
          error -> Errors.to_absinthe(error)
        end
      end)
    end
  end
end
