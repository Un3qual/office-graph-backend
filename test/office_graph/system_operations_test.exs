defmodule OfficeGraph.SystemOperationsTest do
  use OfficeGraph.DataCase, async: false

  import Ecto.Query

  alias OfficeGraph.{DurableDelivery, Foundation, Operations, Repo}
  alias OfficeGraph.Authorization.{Capability, Role, RoleAssignment, RoleCapability}
  alias OfficeGraph.DurableDelivery.{DomainEvent, Subscriptions, SystemConformanceWorker}
  alias OfficeGraph.Identity.Principal
  alias OfficeGraph.Operations.OperationCorrelation

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

  test "operation reads return existing records without requiring a transaction lock" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    principal = system_principal!(bootstrap, "system.conformance")

    assert {:ok, request} =
             bootstrap
             |> system_operation_attrs(principal)
             |> Operations.new_system_operation_request()

    assert {:ok, operation} = Operations.start_system_operation(request)
    assert {:ok, read_operation} = Operations.read_operation(operation.id)
    assert read_operation.id == operation.id

    missing_id = Ecto.UUID.generate()

    assert {:error, {:not_found, OperationCorrelation, ^missing_id}} =
             Operations.read_operation(missing_id)
  end

  test "system operation idempotency is scoped to the exact governing workspace" do
    owner_attrs = [owner_email: "workspace-system-owner@example.test"]

    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        owner_attrs ++
          [
            workspace_name: "System Workspace One",
            workspace_slug: "system-workspace-one",
            initiative_name: "System Initiative One",
            initiative_slug: "system-initiative-one"
          ]
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        owner_attrs ++
          [
            workspace_name: "System Workspace Two",
            workspace_slug: "system-workspace-two",
            initiative_name: "System Initiative Two",
            initiative_slug: "system-initiative-two"
          ]
      )

    principal = system_principal!(first_scope, "system.conformance")

    first_attrs =
      first_scope
      |> system_operation_attrs(principal)
      |> Map.put(:workspace_id, first_scope.workspace.id)

    second_attrs = %{first_attrs | workspace_id: second_scope.workspace.id}

    assert {:ok, first_request} = Operations.new_system_operation_request(first_attrs)
    assert {:ok, second_request} = Operations.new_system_operation_request(second_attrs)
    assert {:ok, first} = Operations.start_system_operation(first_request)
    assert {:ok, second} = Operations.start_system_operation(second_request)
    assert {:ok, first_replay} = Operations.start_system_operation(first_request)

    assert first.id != second.id
    assert first.workspace_id == first_scope.workspace.id
    assert second.workspace_id == second_scope.workspace.id
    assert first_replay.id == first.id
    assert system_operation_count() == 2
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

  test "system principal read outages preserve the retryable storage classification" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    principal = system_principal!(bootstrap, "system.conformance")

    assert {:ok, request} =
             bootstrap
             |> system_operation_attrs(principal)
             |> Operations.new_system_operation_request()

    Repo.query!("SET LOCAL search_path TO pg_catalog")

    result =
      try do
        Operations.start_system_operation(request)
      after
        Repo.query!("SET LOCAL search_path TO public")
      end

    assert {:error, :integration_storage_unavailable} = result
    assert {:ok, _operation} = Operations.start_system_operation(request)
  end

  test "system-operation resource validation rejects missing authenticated envelope fields" do
    attrs = %{
      id: Ecto.UUID.generate(),
      operation_kind: "system",
      principal_id: Ecto.UUID.generate(),
      session_id: nil,
      organization_id: Ecto.UUID.generate(),
      workspace_id: nil,
      action: "integration.reconcile",
      correlation_id: Ecto.UUID.generate(),
      idempotency_key: "missing-system-envelope",
      metadata: %{}
    }

    assert {:error, error} =
             Ash.create(OperationCorrelation, attrs, action: :create, authorize?: false)

    message = Exception.message(error)
    assert message =~ "authority_basis"
    assert message =~ "causation_key"
    assert message =~ "idempotency_scope"
    refute message =~ "constraint error when attempting to insert struct"
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

    [event] = Repo.all(from(event in DomainEvent, where: event.operation_kind == "system"))
    assert length(jobs_for_event(event.id)) == 1
  end

  test "system conformance retries structured persistence failures" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    principal = system_principal!(bootstrap, "system.conformance")

    args = %{
      "organization_id" => bootstrap.organization.id,
      "workspace_id" => nil,
      "principal_id" => principal.id,
      "authority_basis" => "test:durable-delivery",
      "causation_key" => "test:conformance-storage-unavailable",
      "idempotency_key" => "conformance-storage-unavailable"
    }

    assert {:ok, job} = args |> SystemConformanceWorker.new() |> Oban.insert()

    Repo.query!("""
    ALTER TABLE operation_correlations
    ADD CONSTRAINT test_system_conformance_storage_unavailable
    CHECK (action <> 'system.conformance')
    """)

    result =
      try do
        SystemConformanceWorker.perform(job)
      after
        Repo.query!(
          "ALTER TABLE operation_correlations DROP CONSTRAINT test_system_conformance_storage_unavailable"
        )
      end

    assert {:error, "system_conformance_storage_unavailable"} = result
    refute Map.has_key?(Repo.get!(Oban.Job, job.id).meta, "terminal_failure_code")
    assert :ok = SystemConformanceWorker.perform(job)
  end

  test "system conformance event identity is independent across governing workspaces" do
    owner_attrs = [owner_email: "conformance-scope-owner@example.test"]

    {:ok, first_scope} =
      Foundation.bootstrap_local_owner(
        owner_attrs ++
          [
            workspace_name: "Conformance Workspace One",
            workspace_slug: "conformance-workspace-one",
            initiative_name: "Conformance Initiative One",
            initiative_slug: "conformance-initiative-one"
          ]
      )

    {:ok, second_scope} =
      Foundation.bootstrap_local_owner(
        owner_attrs ++
          [
            workspace_name: "Conformance Workspace Two",
            workspace_slug: "conformance-workspace-two",
            initiative_name: "Conformance Initiative Two",
            initiative_slug: "conformance-initiative-two"
          ]
      )

    principal = system_principal!(first_scope, "system.conformance")

    base_args = %{
      "organization_id" => first_scope.organization.id,
      "principal_id" => principal.id,
      "authority_basis" => "test:durable-delivery",
      "causation_key" => "test:cross-workspace-conformance",
      "idempotency_key" => "shared-conformance-key"
    }

    first_job = %Oban.Job{args: Map.put(base_args, "workspace_id", first_scope.workspace.id)}
    second_job = %Oban.Job{args: Map.put(base_args, "workspace_id", second_scope.workspace.id)}

    assert :ok = SystemConformanceWorker.perform(first_job)
    assert :ok = SystemConformanceWorker.perform(second_job)

    events = Repo.all(from(event in DomainEvent, where: event.operation_kind == "system"))

    assert Enum.sort(Enum.map(events, & &1.workspace_id)) ==
             Enum.sort([first_scope.workspace.id, second_scope.workspace.id])

    assert events |> Enum.map(& &1.operation_id) |> Enum.uniq() |> length() == 2
  end

  test "system conformance terminal jobs retain safe failure reasons" do
    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    ungranted = system_principal!(bootstrap, nil)

    cases = [
      {%{
         "organization_id" => bootstrap.organization.id,
         "workspace_id" => nil,
         "principal_id" => ungranted.id,
         "authority_basis" => "test:durable-delivery",
         "causation_key" => "test:forbidden-conformance",
         "idempotency_key" => "forbidden-conformance"
       }, "system_conformance_forbidden"},
      {%{
         "organization_id" => bootstrap.organization.id,
         "workspace_id" => nil
       }, "invalid_system_conformance_job"}
    ]

    jobs =
      Enum.map(cases, fn {args, failure_code} ->
        assert {:ok, job} = args |> SystemConformanceWorker.new() |> Oban.insert()
        assert {:cancel, ^failure_code} = SystemConformanceWorker.perform(job)

        job =
          job
          |> Ecto.Changeset.change(state: "cancelled", cancelled_at: DateTime.utc_now())
          |> Repo.update!()

        {job, failure_code}
      end)

    assert {:ok, summaries} = DurableDelivery.list_terminal_jobs(bootstrap.session)

    for {job, failure_code} <- jobs do
      assert %{failure_code: ^failure_code} = Enum.find(summaries, &(&1.id == job.id))
    end
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
