defmodule OfficeGraph.SystemOperationsTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{DurableDelivery, Foundation, Operations, Repo}
  alias OfficeGraph.Authorization.{Capability, Role, RoleAssignment, RoleCapability}
  alias OfficeGraph.DurableDelivery.{DomainEvent, Subscriptions, SystemConformanceWorker}
  alias OfficeGraph.Identity.Principal

  test "organization-scoped system operations authorize and replay without a human session" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    principal = system_principal!(bootstrap, "system.conformance")

    attrs = system_operation_attrs(bootstrap, principal)

    assert {:ok, request} = Operations.new_system_operation_request(attrs)
    assert {:ok, first} = Operations.start_system_operation(request)
    assert {:ok, replay} = Operations.start_system_operation(request)

    assert replay.id == first.id
    assert first.operation_kind == "system"
    assert first.organization_id == bootstrap.organization.id
    assert first.principal_id == principal.id
    assert is_nil(first.session_id)
    assert is_nil(first.workspace_id)
    assert first.authority_basis == attrs.authority_basis
    assert first.causation_key == attrs.causation_key
    assert first.idempotency_scope == attrs.idempotency_scope
    assert first.idempotency_key == attrs.idempotency_key
    assert is_nil(first.subject_id)

    changed = %{attrs | authority_basis: "test:other-authority"}
    assert {:ok, changed_request} = Operations.new_system_operation_request(changed)

    assert {:error, {:system_idempotency_conflict, operation_id}} =
             Operations.start_system_operation(changed_request)

    assert operation_id == first.id
    assert system_operation_count() == 1
  end

  test "system operations fail closed for human principals, missing authority, and missing grants" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    ungranted = system_principal!(bootstrap, nil)

    assert {:error, {:missing_field, :authority_basis}} =
             bootstrap
             |> system_operation_attrs(ungranted)
             |> Map.delete(:authority_basis)
             |> Operations.new_system_operation_request()

    assert {:ok, ungranted_request} =
             bootstrap
             |> system_operation_attrs(ungranted)
             |> Operations.new_system_operation_request()

    assert {:error, :forbidden} = Operations.start_system_operation(ungranted_request)

    assert {:ok, human_request} =
             bootstrap
             |> system_operation_attrs(bootstrap.principal)
             |> Operations.new_system_operation_request()

    assert {:error, :forbidden} = Operations.start_system_operation(human_request)
    assert system_operation_count() == 0
  end

  test "organization-scoped events retain system authority and enqueue once" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    principal = system_principal!(bootstrap, "system.conformance")

    assert {:ok, request} =
             bootstrap
             |> system_operation_attrs(principal)
             |> Operations.new_system_operation_request()

    assert {:ok, operation} = Operations.start_system_operation(request)

    attrs = %{
      event_key: "system:test:#{operation.id}",
      event_kind: "system_conformance.completed"
    }

    assert {:ok, first} = DurableDelivery.record_system_and_enqueue(operation, attrs)
    assert {:ok, replay} = DurableDelivery.record_system_and_enqueue(operation, attrs)

    assert replay.id == first.id
    assert first.event_scope == "organization"
    assert first.organization_id == bootstrap.organization.id
    assert is_nil(first.workspace_id)
    assert is_nil(first.subject_kind)
    assert is_nil(first.subject_id)
    assert is_nil(first.subject_version)

    assert [%Oban.Job{} = job] = jobs_for_event(first.id)

    assert job.args == %{
             "event_id" => first.id,
             "organization_id" => bootstrap.organization.id,
             "workspace_id" => nil
           }
  end

  test "a non-GitHub worker proves generic system-operation delivery" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    principal = system_principal!(bootstrap, "system.conformance")

    job = %Oban.Job{
      args: %{
        "organization_id" => bootstrap.organization.id,
        "principal_id" => principal.id,
        "authority_basis" => "test:durable-delivery",
        "causation_key" => "test:scheduled-conformance",
        "idempotency_key" => "conformance-1"
      }
    }

    assert :ok = SystemConformanceWorker.perform(job)
    assert :ok = SystemConformanceWorker.perform(job)

    assert system_operation_count() == 1
    assert system_event_count() == 1

    [event] = Repo.all(DomainEvent) |> Enum.filter(&(&1.operation_kind == "system"))
    assert length(jobs_for_event(event.id)) == 1
  end

  test "human operation and event invariants remain session and workspace scoped" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    invalid_session = %{bootstrap.session | workspace_id: nil}

    assert {:error, :forbidden} =
             Operations.start_operation(invalid_session, :manual_intake_submit)

    assert {:ok, operation} =
             Operations.start_operation(bootstrap.session, :manual_intake_submit)

    assert operation.operation_kind == "human"
    assert operation.session_id == bootstrap.session.session_id
    assert operation.workspace_id == bootstrap.workspace.id
    assert is_nil(operation.authority_basis)

    assert {:error, {:missing_field, :subject_id}} =
             DurableDelivery.record_and_enqueue(bootstrap.session, operation, %{
               event_key: "human:subject-required",
               event_kind: "manual_intake.accepted",
               subject_kind: "normalized_intake_event"
             })
  end

  defp system_operation_attrs(bootstrap, principal) do
    %{
      organization_id: bootstrap.organization.id,
      principal_id: principal.id,
      action: :system_conformance,
      authority_basis: "test:durable-delivery",
      causation_key: "test:scheduled-conformance",
      idempotency_scope: "durable-delivery:conformance",
      idempotency_key: "conformance-1"
    }
  end

  defp system_principal!(bootstrap, capability_key) do
    principal =
      Principal
      |> Ash.Changeset.for_create(:create, %{
        id: Ecto.UUID.generate(),
        email: "system-#{Ecto.UUID.generate()}@office-graph.local",
        kind: "service",
        status: "active"
      })
      |> Ash.create!(authorize?: false)

    if capability_key do
      capability = capability!(capability_key)

      role =
        Role
        |> Ash.Changeset.for_create(:create, %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          key: "system-conformance-#{principal.id}",
          name: "System conformance"
        })
        |> Ash.create!(authorize?: false)

      RoleCapability
      |> Ash.Changeset.for_create(:create, %{
        id: Ecto.UUID.generate(),
        role_id: role.id,
        capability_id: capability.id
      })
      |> Ash.create!(authorize?: false)

      RoleAssignment
      |> Ash.Changeset.for_create(:create, %{
        id: Ecto.UUID.generate(),
        principal_id: principal.id,
        role_id: role.id,
        organization_id: bootstrap.organization.id,
        workspace_id: nil
      })
      |> Ash.create!(authorize?: false)
    end

    principal
  end

  defp jobs_for_event(event_id) do
    Oban.Job
    |> where([job], fragment("?->>'event_id'", job.args) == ^event_id)
    |> Repo.all()
  end

  defp system_operation_count do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM operation_correlations WHERE operation_kind = 'system'")

    count
  end

  defp system_event_count do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM domain_events WHERE operation_kind = 'system'")

    count
  end

  defp capability!(key) do
    case Ash.get(Capability, %{key: key}, authorize?: false) do
      {:ok, nil} ->
        Capability
        |> Ash.Changeset.for_create(:create, %{
          id: Ecto.UUID.generate(),
          key: key,
          description: key
        })
        |> Ash.create!(authorize?: false)

      {:ok, capability} ->
        capability
    end
  end

  test "organization-scoped dispatch publishes only a safe organization invalidation" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    principal = system_principal!(bootstrap, "system.conformance")

    assert {:ok, request} =
             bootstrap
             |> system_operation_attrs(principal)
             |> Operations.new_system_operation_request()

    assert {:ok, operation} = Operations.start_system_operation(request)

    assert {:ok, event} =
             DurableDelivery.record_system_and_enqueue(operation, %{
               event_key: "system:organization-invalidation:#{operation.id}",
               event_kind: "system_conformance.completed"
             })

    assert :ok =
             Phoenix.PubSub.subscribe(
               OfficeGraph.PubSub,
               Subscriptions.organization_topic(bootstrap.organization.id)
             )

    assert :ok = DurableDelivery.dispatch(event.id)

    assert_receive {:projection_invalidated, invalidation}
    assert invalidation.organization_id == bootstrap.organization.id
    assert is_nil(invalidation.workspace_id)
    assert is_nil(invalidation.subject_id)
  end
end
