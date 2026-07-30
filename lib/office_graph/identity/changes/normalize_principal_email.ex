defmodule OfficeGraph.Identity.Changes.NormalizePrincipalEmail do
  @moduledoc false

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :email) do
      email when is_binary(email) ->
        normalized_email =
          email
          |> String.trim()
          |> String.downcase()

        Ash.Changeset.force_change_attribute(changeset, :email, normalized_email)

      _missing_or_invalid_email ->
        changeset
    end
  end
end
