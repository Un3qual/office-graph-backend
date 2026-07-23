defmodule OfficeGraph.AgentRuntime.OrganizationBindingTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Authorization, Foundation, Repo}
  alias OfficeGraph.AgentRuntime.{AgentDefinition, OrganizationBinding}
  alias OfficeGraph.Authorization.RoleAssignment
  alias OfficeGraph.Identity.{Principal, Session, SessionContext}
  alias OfficeGraph.Tenancy.Workspace

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

    for action <- [
          :agent_invoke,
          :agent_model_generate,
          :agent_tool_read,
          :agent_proposal_create,
          :agent_repository_read,
          :agent_openspec_read,
          :agent_evidence_suggest
        ] do
      assert :ok =
               Authorization.authorize_system_principal(
                 first.principal.id,
                 bootstrap.organization.id,
                 bootstrap.workspace.id,
                 action
               )
    end

    assert Repo.aggregate(OrganizationBinding, :count) == 1
  end

  test "an authorized repeat bind with a new operation returns the active scoped binding" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:ok, first} =
             AgentRuntime.bind_openspec_review_agent(bootstrap.session, %{
               idempotency_key: "bind-openspec-review-first"
             })

    assert {:ok, repeated} =
             AgentRuntime.bind_openspec_review_agent(bootstrap.session, %{
               idempotency_key: "bind-openspec-review-repeated"
             })

    assert repeated.binding.id == first.binding.id
    refute repeated.operation.id == first.operation.id
    assert repeated.binding.operation_id == first.operation.id
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

  test "workspaces in one organization receive isolated bindings and scoped authority" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    second_session = create_workspace_session!(bootstrap)

    assert {:ok, first} =
             AgentRuntime.bind_openspec_review_agent(bootstrap.session, %{
               idempotency_key: "bind-same-organization"
             })

    assert {:ok, second} =
             AgentRuntime.bind_openspec_review_agent(second_session, %{
               idempotency_key: "bind-same-organization"
             })

    refute first.binding.id == second.binding.id
    assert first.principal.id == second.principal.id
    assert first.binding.organization_id == second.binding.organization_id
    refute first.binding.workspace_id == second.binding.workspace_id

    assert :ok =
             Authorization.authorize_system_principal(
               second.principal.id,
               second_session.organization_id,
               second_session.workspace_id,
               :agent_runtime_execute
             )

    assert Repo.aggregate(OrganizationBinding, :count) == 2
  end

  test "binding lifecycle updates keep disabled timestamps consistent" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])

    assert {:ok, result} =
             AgentRuntime.bind_openspec_review_agent(bootstrap.session, %{
               idempotency_key: "bind-lifecycle"
             })

    assert {:ok, disabled} =
             result.binding
             |> Ash.Changeset.for_update(:set_lifecycle_state, %{lifecycle_state: "disabled"})
             |> Ash.update(authorize?: false)

    assert disabled.lifecycle_state == "disabled"
    assert %DateTime{} = disabled.disabled_at

    assert {:ok, active} =
             disabled
             |> Ash.Changeset.for_update(:set_lifecycle_state, %{lifecycle_state: "active"})
             |> Ash.update(authorize?: false)

    assert active.lifecycle_state == "active"
    assert is_nil(active.disabled_at)
  end

  defp create_workspace_session!(bootstrap) do
    suffix = System.unique_integer([:positive])

    workspace =
      Ash.create!(
        Workspace,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          name: "Agent Runtime Workspace #{suffix}",
          slug: "agent-runtime-workspace-#{suffix}"
        },
        action: :create,
        authorize?: false
      )

    session =
      Ash.create!(
        Session,
        %{
          id: Ecto.UUID.generate(),
          principal_id: bootstrap.principal.id,
          organization_id: bootstrap.organization.id,
          workspace_id: workspace.id,
          purpose: "agent-runtime-workspace-#{suffix}"
        },
        action: :create,
        authorize?: false
      )

    Ash.create!(
      RoleAssignment,
      %{
        id: Ecto.UUID.generate(),
        principal_id: bootstrap.principal.id,
        role_id: bootstrap.role_assignment.role_id,
        organization_id: bootstrap.organization.id,
        workspace_id: workspace.id
      },
      action: :create,
      authorize?: false
    )

    %SessionContext{
      principal_id: bootstrap.principal.id,
      session_id: session.id,
      organization_id: bootstrap.organization.id,
      workspace_id: workspace.id,
      capabilities: bootstrap.session.capabilities,
      trusted?: bootstrap.session.trusted?
    }
  end
end
