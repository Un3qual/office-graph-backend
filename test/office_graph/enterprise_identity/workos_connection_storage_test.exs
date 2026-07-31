defmodule OfficeGraph.EnterpriseIdentity.WorkOSConnectionStorageTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.EnterpriseIdentity
  alias OfficeGraph.EnterpriseIdentity.EnterpriseConnection

  test "active connection results distinguish absence from storage failure" do
    connection = %EnterpriseConnection{}

    assert {:ok, ^connection} =
             EnterpriseIdentity.classify_active_connection_result({:ok, connection})

    assert {:error, :enterprise_connection_unavailable} =
             EnterpriseIdentity.classify_active_connection_result({:ok, nil})

    assert {:error, :enterprise_identity_storage_unavailable} =
             EnterpriseIdentity.classify_active_connection_result(
               {:error, Ash.Error.Unknown.exception(errors: [])}
             )
  end
end
