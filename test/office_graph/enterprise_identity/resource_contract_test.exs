defmodule OfficeGraph.EnterpriseIdentity.ResourceContractTest do
  use OfficeGraph.DataCase, async: true

  alias OfficeGraph.EnterpriseIdentity.{
    Directory,
    DirectoryGroup,
    DirectoryMembership,
    DirectorySyncEvent,
    DirectoryUser,
    EnterpriseConnection,
    ExternalGroupRoleMapping
  }

  @resources [
    EnterpriseConnection,
    Directory,
    DirectoryUser,
    DirectoryGroup,
    DirectoryMembership,
    DirectorySyncEvent,
    ExternalGroupRoleMapping
  ]

  test "enterprise identity resources use AshPostgres and database-generated UUIDv7 ids" do
    Enum.each(@resources, fn resource ->
      assert Ash.DataLayer.data_layer(resource) == AshPostgres.DataLayer
      assert AshPostgres.DataLayer.Info.migrate?(resource)

      primary_key = Ash.Resource.Info.attribute(resource, :id)

      assert primary_key.type == Ash.Type.UUID
      assert primary_key.generated?
      assert primary_key.writable?
      refute primary_key.default
    end)
  end

  test "directory resources expose the typed ownership relationships" do
    assert relationship_names(EnterpriseConnection) ==
             MapSet.new([
               :organization,
               :workspace,
               :webhook_principal,
               :operation,
               :directories,
               :sync_events
             ])

    assert relationship_names(Directory) ==
             MapSet.new([:connection, :operation, :users, :groups, :sync_events])

    assert relationship_names(DirectoryUser) ==
             MapSet.new([
               :directory,
               :principal,
               :external_identity_link,
               :memberships
             ])

    assert relationship_names(DirectoryGroup) ==
             MapSet.new([:directory, :memberships])

    assert relationship_names(DirectoryMembership) ==
             MapSet.new([:directory_user, :directory_group])

    assert relationship_names(DirectorySyncEvent) ==
             MapSet.new([:connection, :directory, :raw_archive, :operation])

    assert relationship_names(ExternalGroupRoleMapping) ==
             MapSet.new([
               :directory_group,
               :role,
               :organization,
               :workspace,
               :operation
             ])
  end

  test "active directory membership and group mapping identities use in-table slots" do
    membership_identity =
      Ash.Resource.Info.identity(DirectoryMembership, :active_membership)

    mapping_identity =
      Ash.Resource.Info.identity(ExternalGroupRoleMapping, :active_mapping)

    assert membership_identity.keys ==
             [:directory_user_id, :directory_group_id, :active_identity_slot]

    assert mapping_identity.keys == [
             :directory_group_id,
             :role_id,
             :organization_id,
             :workspace_id,
             :active_identity_slot
           ]

    for resource <- [DirectoryMembership, ExternalGroupRoleMapping] do
      slot = Ash.Resource.Info.attribute(resource, :active_identity_slot)

      assert slot.type == Ash.Type.String
      refute slot.public?
      refute slot.writable?
    end
  end

  defp relationship_names(resource) do
    resource
    |> Ash.Resource.Info.relationships()
    |> Enum.map(& &1.name)
    |> MapSet.new()
  end
end
