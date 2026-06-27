defmodule OfficeGraphWeb.GraphQL.Compatibility.Mutations do
  use Absinthe.Schema.Notation

  alias OfficeGraph.ApiSupport
  alias OfficeGraphWeb.GraphQL.Common.Errors

  object :compatibility_mutations do
    field :submit_manual_intake, non_null(:manual_intake_payload) do
      arg(:input, non_null(:manual_intake_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.submit_manual_intake(input) do
          {:ok, intake} ->
            {:ok,
             %{
               normalized_event: intake.normalized_event,
               proposed_changes: intake.proposed_changes
             }}

          error ->
            Errors.to_absinthe(error)
        end
      end)
    end

    field :apply_proposed_changes, non_null(:applied_payload) do
      arg(:input, non_null(:apply_proposed_changes_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.apply_proposed_changes(input) do
          {:ok, applied} -> {:ok, applied}
          error -> Errors.to_absinthe(error)
        end
      end)
    end

    field :complete_verification, non_null(:completed_payload) do
      arg(:input, non_null(:complete_verification_input))

      resolve(fn %{input: input}, _ ->
        case ApiSupport.complete_verification(input) do
          {:ok, completed} -> {:ok, completed}
          error -> Errors.to_absinthe(error)
        end
      end)
    end
  end
end
