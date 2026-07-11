defmodule OfficeGraph.WorkGraph.VerificationResult.ValidateResultEvidence do
  @moduledoc false

  use Ash.Resource.Change

  alias OfficeGraph.WorkGraph.EvidenceItem

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    result = Ash.Changeset.get_attribute(changeset, :result)
    verification_check_id = Ash.Changeset.get_attribute(changeset, :verification_check_id)
    evidence_item_id = Ash.Changeset.get_attribute(changeset, :evidence_item_id)

    case result do
      "waived" ->
        require_nil_evidence(changeset, evidence_item_id)

      result when result in ["passed", "failed"] ->
        require_matching_evidence(
          changeset,
          evidence_item_id,
          verification_check_id
        )

      _other ->
        Ash.Changeset.add_error(changeset, field: :result, message: "is invalid")
    end
  end

  @doc false
  def evidence_matches_check?(
        evidence_item_id,
        verification_check_id,
        fetch_evidence_item \\ &fetch_evidence_item/1
      ) do
    evidence_item_id
    |> fetch_evidence_item.()
    |> case do
      {:ok, %{verification_check_id: ^verification_check_id}} -> true
      {:ok, _missing_or_mismatch} -> false
      {:error, _error} -> false
    end
  end

  defp require_nil_evidence(changeset, nil), do: changeset

  defp require_nil_evidence(changeset, _evidence_item_id) do
    Ash.Changeset.add_error(changeset,
      field: :evidence_item_id,
      message: "must be empty for waived results"
    )
  end

  defp require_matching_evidence(changeset, nil, _verification_check_id) do
    Ash.Changeset.add_error(changeset,
      field: :evidence_item_id,
      message: "is required for passed or failed results"
    )
  end

  defp require_matching_evidence(changeset, evidence_item_id, verification_check_id) do
    if evidence_matches_check?(evidence_item_id, verification_check_id) do
      changeset
    else
      Ash.Changeset.add_error(changeset,
        field: :evidence_item_id,
        message: "must belong to verification_check_id"
      )
    end
  end

  defp fetch_evidence_item(evidence_item_id) do
    EvidenceItem
    |> Ash.Query.filter(id == ^evidence_item_id)
    |> Ash.read_one(authorize?: false)
  end
end
