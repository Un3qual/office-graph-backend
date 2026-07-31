defmodule OfficeGraph.CommandSupportTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.CommandSupport

  test "unique constraint matching treats absent private metadata as non-matching" do
    error = %Ash.Error.Invalid{
      errors: [
        Ash.Error.Changes.InvalidAttribute.exception(
          field: :email,
          message: "is invalid"
        )
      ]
    }

    refute CommandSupport.unique_constraint?(error, "principals_email_index")
  end

  test "unique constraint matching accepts one exact constraint from a bounded set" do
    error = %Ash.Error.Invalid{
      errors: [
        Ash.Error.Changes.InvalidAttribute.exception(
          field: :email,
          message: "has already been taken",
          private_vars: [
            constraint_type: :unique,
            constraint: "principals_email_index"
          ]
        )
      ]
    }

    assert CommandSupport.unique_constraint?(error, [
             "principals_email_index",
             "principal_profiles_principal_id_index"
           ])

    refute CommandSupport.unique_constraint?(error, "external_identity_links_subject_index")
  end
end
