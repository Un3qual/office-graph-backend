defmodule OfficeGraph.GitHubIntegration.InstallationMigrationTest do
  use OfficeGraph.DataCase, async: false

  import OfficeGraph.TestSupport.PostgresCatalog

  @tables ~w(github_installations github_permission_snapshots github_permission_entries integration_credentials github_installation_credentials)

  test "installation authority and credential metadata use relational tables and constraints" do
    for table <- @tables do
      assert table_exists?(table)
    end

    assert constraint_exists?("github_installations_lifecycle_state_valid")
    assert constraint_exists?("github_permission_entries_access_level_valid")
    assert constraint_exists?("integration_credentials_status_valid")
    assert constraint_exists?("github_installation_credentials_purpose_valid")
    assert index_exists?("github_installations_external_installation_id_index")
    assert index_exists?("github_permission_entries_snapshot_name_index")
    assert index_exists?("github_installation_credentials_installation_purpose_index")

    refute column_exists?("integration_credentials", "secret_value")
    refute column_exists?("github_installations", "private_key")
    refute column_exists?("github_installations", "webhook_secret")
  end
end
