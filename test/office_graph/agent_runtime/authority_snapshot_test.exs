defmodule OfficeGraph.AgentRuntime.AuthoritySnapshotTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{AgentRuntime, Authorization, Repo}
  alias OfficeGraph.AgentRuntime.{ApprovalRequest, AuthoritySnapshot}
  alias OfficeGraph.Authorization.PolicyBundle
  alias OfficeGraph.Integrations.IntegrationCredential
  alias OfficeGraph.TestSupport.AgentRuntimeSupport

  setup do
    context = AgentRuntimeSupport.invocation_fixture()
    {:ok, Map.put(context, :invocation, AgentRuntimeSupport.invoke_human(context))}
  end

  test "invocation snapshots the effective requested authority and active policy", context do
    snapshot = context.invocation.authority_snapshot

    assert snapshot.version == 1
    assert snapshot.organization_id == context.bootstrap.organization.id
    assert snapshot.workspace_id == context.bootstrap.workspace.id
    assert snapshot.agent_principal_id == context.agent_principal.id
    assert snapshot.delegator_principal_id == context.bootstrap.principal.id
    assert snapshot.operation_id == context.invocation.operation.id
    assert snapshot.capability_keys == ["proposal.create", "repository.read"]
    assert snapshot.tool_keys == ["openspec.read", "repository.read"]
    assert snapshot.credential_ids == []
    assert snapshot.autonomy_mode == "human_supervised"
    assert snapshot.policy_bundle_id == context.bootstrap.policy_bundle.id
    assert snapshot.policy_bundle_version == context.bootstrap.policy_bundle.version
    assert snapshot.authority_hash =~ ~r/^[a-f0-9]{64}$/

    assert Ash.Resource.Info.actions(AuthoritySnapshot)
           |> Enum.map(& &1.type)
           |> Enum.sort() == [:create, :read]
  end

  test "unsupported requested authority is rejected instead of silently widening or downgrading",
       context do
    request =
      AgentRuntimeSupport.request(context, %{
        idempotency_key: "unsupported-authority-#{context.suffix}",
        requested_capabilities: ["external.write"]
      })

    assert {:ok, operation} = AgentRuntimeSupport.human_operation(context.session, request)

    assert {:error, {:unsupported_agent_capabilities, ["external.write"]}} =
             AgentRuntime.invoke(context.session, operation, request)
  end

  test "pre-step revalidation fails closed after principal or grant revocation", context do
    execution_id = context.invocation.execution.id

    assert :ok = AgentRuntime.revalidate_step(execution_id)

    Repo.query!("UPDATE principals SET status = 'inactive', updated_at = now() WHERE id = $1", [
      Ecto.UUID.dump!(context.agent_principal.id)
    ])

    assert {:error, :agent_principal_inactive} = AgentRuntime.revalidate_step(execution_id)

    Repo.query!("UPDATE principals SET status = 'active', updated_at = now() WHERE id = $1", [
      Ecto.UUID.dump!(context.agent_principal.id)
    ])

    role_assignment_ids =
      Repo.query!(
        "SELECT id FROM role_assignments WHERE principal_id = $1 AND organization_id = $2 AND workspace_id = $3",
        [
          Ecto.UUID.dump!(context.agent_principal.id),
          Ecto.UUID.dump!(context.bootstrap.organization.id),
          Ecto.UUID.dump!(context.bootstrap.workspace.id)
        ]
      ).rows
      |> List.flatten()

    Repo.query!("DELETE FROM role_assignments WHERE id = ANY($1::uuid[])", [role_assignment_ids])

    assert {:error, :agent_authority_revoked} = AgentRuntime.revalidate_step(execution_id)
  end

  test "pre-step revalidation fails closed when the active organization policy changes",
       context do
    execution_id = context.invocation.execution.id

    assert :ok = AgentRuntime.revalidate_step(execution_id)

    Ash.create!(
      PolicyBundle,
      %{
        id: Ecto.UUID.generate(),
        organization_id: context.bootstrap.organization.id,
        version: context.bootstrap.policy_bundle.version + 1,
        status: "active"
      },
      action: :create,
      authorize?: false
    )

    assert {:error, :authority_policy_changed} = AgentRuntime.revalidate_step(execution_id)
  end

  test "pre-step revalidation fails closed when run autonomy no longer matches the snapshot",
       context do
    execution_id = context.invocation.execution.id

    assert :ok = AgentRuntime.revalidate_step(execution_id)

    Repo.query!(
      "UPDATE work_packet_versions SET autonomy_posture = 'bounded_automatic', updated_at = now() WHERE id = $1",
      [Ecto.UUID.dump!(context.packet_version.id)]
    )

    assert {:error, :run_authority_revoked} = AgentRuntime.revalidate_step(execution_id)
  end

  test "pre-step revalidation checks current tool eligibility and matching approval", context do
    execution = context.invocation.execution
    snapshot = context.invocation.authority_snapshot

    assert :ok = AgentRuntime.revalidate_step(execution.id, tool_key: "repository.read")

    assert {:error, :tool_not_authorized} =
             AgentRuntime.revalidate_step(execution.id, tool_key: "arbitrary.shell")

    approval =
      Ash.create!(
        ApprovalRequest,
        %{
          id: Ecto.UUID.generate(),
          execution_id: execution.id,
          authority_snapshot_id: snapshot.id,
          organization_id: execution.organization_id,
          workspace_id: execution.workspace_id,
          operation_id: execution.operation_id,
          step_key: "tool:repository.read",
          requested_action: "repository.read",
          reason: "Confirm bounded repository context.",
          scope_type: "work_run",
          scope_id: execution.run_id,
          capability_key: "repository.read",
          sensitivity: "internal",
          external_write: false,
          state: "approved",
          expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
        },
        action: :create,
        authorize?: false
      )

    assert :ok =
             AgentRuntime.revalidate_step(execution.id,
               tool_key: "repository.read",
               approval_request_id: approval.id
             )

    approval
    |> Ash.Changeset.for_update(:resolve, %{state: "cancelled", version: 2})
    |> Ash.update!(authorize?: false)

    assert {:error, :approval_not_active} =
             AgentRuntime.revalidate_step(execution.id,
               tool_key: "repository.read",
               approval_request_id: approval.id
             )

    assert :ok =
             Authorization.authorize_system_principal(
               context.agent_principal.id,
               context.bootstrap.organization.id,
               context.bootstrap.workspace.id,
               :agent_runtime_execute
             )
  end

  test "credential metadata is snapshotted and revoked credentials stop later steps", context do
    credential =
      Ash.create!(
        IntegrationCredential,
        %{
          id: Ecto.UUID.generate(),
          organization_id: context.bootstrap.organization.id,
          workspace_id: context.bootstrap.workspace.id,
          kind: "secret_reference",
          secret_reference: "test-secret://agent-runtime/model/#{context.suffix}",
          status: "active",
          operation_id: context.binding.operation_id
        },
        action: :create,
        authorize?: false
      )

    Repo.query!("UPDATE agent_definitions SET model_credential_id = $1 WHERE id = $2", [
      Ecto.UUID.dump!(credential.id),
      Ecto.UUID.dump!(context.definition.id)
    ])

    invocation =
      AgentRuntimeSupport.invoke_human(context, %{
        idempotency_key: "credential-invocation-#{context.suffix}"
      })

    assert invocation.authority_snapshot.credential_ids == [credential.id]
    assert :ok = AgentRuntime.revalidate_step(invocation.execution.id)

    credential
    |> Ash.Changeset.for_update(:set_status, %{status: "revoked"})
    |> Ash.update!(authorize?: false)

    assert {:error, :credential_inactive} =
             AgentRuntime.revalidate_step(invocation.execution.id)
  end
end
