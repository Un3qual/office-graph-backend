defmodule OfficeGraph.AgentRuntime.OrganizationBindingTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Authorization, Foundation, Repo}
  alias OfficeGraph.AgentRuntime.{AgentDefinition, OrganizationBinding}
  alias OfficeGraph.Identity.Principal

  import OfficeGraph.SessionCaseHelpers

  setup do
    assert Code.ensure_loaded?(AgentRuntime)

    assert function_exported?(AgentRuntime, :bind_openspec_review_agent, 2),
           "expected the narrow OpenSpec-review binding command"

    :ok
  end

  test "authorized owners bind and replay the canonical definition with a backend agent principal" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    attrs = %{idempotency_key: "bind-openspec-review"}

    assert {:ok, first} = AgentRuntime.bind_openspec_review_agent(bootstrap.session, attrs)
    assert {:ok, replay} = AgentRuntime.bind_openspec_review_agent(bootstrap.session, attrs)

    assert replay.operation.id == first.operation.id
    assert replay.binding.id == first.binding.id
    assert replay.principal.id == first.principal.id
    assert first.definition.key == "openspec-review"
    assert first.definition.lifecycle_state == "active"
    assert first.binding.organization_id == bootstrap.organization.id
    assert first.binding.workspace_id == bootstrap.workspace.id
    assert first.binding.bound_by_principal_id == bootstrap.principal.id
    assert first.binding.lifecycle_state == "active"
    assert first.principal.kind == "agent"
    assert first.principal.status == "active"

    assert :ok =
             Authorization.authorize_system_principal(
               first.principal.id,
               bootstrap.organization.id,
               bootstrap.workspace.id,
               :agent_runtime_execute
             )

    assert :ok =
             Authorization.authorize_system_principal(
               first.principal.id,
               bootstrap.organization.id,
               bootstrap.workspace.id,
               :skeleton_read
             )

    assert Repo.aggregate(OrganizationBinding, :count) == 1
  end

  test "binding rejects missing authority, forged scope, generic definition input, and inactive definition" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    no_capabilities =
      create_session_with_capabilities!(bootstrap, [], prefix: "agent-bind-denied")

    principal_count = Repo.aggregate(Principal, :count)

    assert {:error, :forbidden} =
             AgentRuntime.bind_openspec_review_agent(no_capabilities, %{
               idempotency_key: "agent-bind-denied"
             })

    assert Repo.aggregate(OrganizationBinding, :count) == 0
    assert Repo.aggregate(Principal, :count) == principal_count

    forged_scope = %{bootstrap.session | organization_id: Ecto.UUID.generate()}

    assert {:error, :forbidden} =
             AgentRuntime.bind_openspec_review_agent(forged_scope, %{
               idempotency_key: "agent-bind-forged"
             })

    assert {:error, :forbidden} =
             AgentRuntime.bind_openspec_review_agent(nil, %{
               idempotency_key: "agent-bind-invalid-session"
             })

    assert {:error, {:invalid_field, :definition_key}} =
             AgentRuntime.bind_openspec_review_agent(bootstrap.session, %{
               idempotency_key: "agent-bind-generic",
               definition_key: "another-agent"
             })

    definition = Ash.get!(AgentDefinition, %{key: "openspec-review"}, authorize?: false)

    definition
    |> Ash.Changeset.for_update(:set_lifecycle_state, %{lifecycle_state: "disabled"})
    |> Ash.update!(authorize?: false)

    assert {:error, :forbidden} =
             AgentRuntime.bind_openspec_review_agent(bootstrap.session, %{
               idempotency_key: "agent-bind-disabled"
             })

    assert Repo.aggregate(OrganizationBinding, :count) == 0
  end

  test "separate organizations receive isolated bindings and principals" do
    suffix = System.unique_integer([:positive])

    {:ok, first} = Foundation.bootstrap_local_owner([])

    {:ok, second} =
      Foundation.bootstrap_local_owner(
        organization_name: "Agent Runtime Organization #{suffix}",
        organization_slug: "agent-runtime-organization-#{suffix}",
        workspace_name: "Agent Runtime Workspace #{suffix}",
        workspace_slug: "agent-runtime-workspace-#{suffix}",
        initiative_name: "Agent Runtime Initiative #{suffix}",
        initiative_slug: "agent-runtime-initiative-#{suffix}",
        owner_email: "agent-runtime-owner-#{suffix}@office-graph.local"
      )

    assert {:ok, first_binding} =
             AgentRuntime.bind_openspec_review_agent(first.session, %{
               idempotency_key: "bind-shared-key"
             })

    assert {:ok, second_binding} =
             AgentRuntime.bind_openspec_review_agent(second.session, %{
               idempotency_key: "bind-shared-key"
             })

    refute first_binding.binding.id == second_binding.binding.id
    refute first_binding.principal.id == second_binding.principal.id
    assert first_binding.binding.organization_id == first.organization.id
    assert second_binding.binding.organization_id == second.organization.id
    assert Repo.aggregate(OrganizationBinding, :count) == 2
  end
end
