defmodule OfficeGraph.WorkGraph.RelationshipMigrationTest do
  use OfficeGraph.DataCase, async: false

  alias OfficeGraph.{Foundation, Operations, Repo}

  @typed_migration_version 20_260_713_101_000
  @typed_migration_module OfficeGraph.Repo.Migrations.TypeGraphRelationships
  @constraint_migration_version 20_260_713_103_000
  @constraint_migration_module OfficeGraph.Repo.Migrations.HardenRelationshipPolicyConstraints

  test "all legacy edge values become canonical typed edges and roll back losslessly" do
    run_migration!(:down)

    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)
    legacy = insert_legacy_relationships!(bootstrap, operation)

    run_migration!(:up)

    task = relationship_by_id!(legacy.produced_task_relationship_id)
    assert task.definition_key == "generated_from"
    assert task.source_item_id == legacy.task_item_id
    assert task.target_item_id == legacy.signal_item_id

    review = relationship_by_id!(legacy.review_relationship_id)
    assert review.definition_key == "review_finding_for"
    assert review.source_item_id == legacy.review_finding_item_id
    assert review.target_item_id == legacy.task_item_id

    check = relationship_by_id!(legacy.check_relationship_id)
    assert check.definition_key == "requires_check"
    assert check.source_item_id == legacy.review_finding_item_id
    assert check.target_item_id == legacy.verification_check_item_id

    evidence = relationship_by_id!(legacy.evidence_relationship_id)
    assert evidence.definition_key == "evidenced_by"
    assert evidence.source_item_id == legacy.verification_check_item_id
    assert evidence.target_item_id == legacy.evidence_item_id

    artifact = relationship_by_id!(legacy.artifact_relationship_id)
    assert artifact.definition_key == "generated_from"
    assert artifact.source_item_id == legacy.evidence_item_id
    assert artifact.target_item_id == legacy.artifact_item_id

    for relationship <- [task, review, check, evidence, artifact] do
      assert relationship.organization_id == bootstrap.organization.id
      assert relationship.workspace_id == bootstrap.workspace.id
      assert relationship.lifecycle == "active"
      assert relationship.asserting_principal_id == bootstrap.principal.id
      assert relationship.operation_id == operation.id
      assert %NaiveDateTime{} = relationship.valid_from
      assert is_nil(relationship.valid_until)
    end

    refute column_exists?("graph_relationships", "relationship_type")
    assert constraint_exists?("graph_relationships_lifecycle_window_valid")

    run_migration!(:down)

    assert legacy_relationship!(legacy.produced_task_relationship_id) ==
             {legacy.signal_item_id, legacy.task_item_id, "produced_task"}

    assert legacy_relationship!(legacy.review_relationship_id) ==
             {legacy.task_item_id, legacy.review_finding_item_id, "has_review_finding"}

    assert legacy_relationship!(legacy.check_relationship_id) ==
             {legacy.review_finding_item_id, legacy.verification_check_item_id,
              "requires_verification"}

    assert legacy_relationship!(legacy.evidence_relationship_id) ==
             {legacy.verification_check_item_id, legacy.evidence_item_id, "has_evidence"}

    assert legacy_relationship!(legacy.artifact_relationship_id) ==
             {legacy.evidence_item_id, legacy.artifact_item_id, "references_artifact"}
  end

  test "unknown legacy values abort before changing rows" do
    run_migration!(:down)

    {:ok, bootstrap} = Foundation.bootstrap_local_owner([])
    {:ok, operation} = Operations.start_operation(bootstrap.session, :proposed_change_apply)

    source_id = insert_graph_item!(bootstrap, "task")
    target_id = insert_graph_item!(bootstrap, "task")
    relationship_id = insert_legacy_relationship!(source_id, target_id, "unknown_edge")
    insert_audit!(bootstrap, operation, "task", graph_resource_id!(target_id), "task.create")

    assert_raise Postgrex.Error, ~r/unknown graph relationship types.*unknown_edge/, fn ->
      run_migration!(:up)
    end

    assert legacy_relationship!(relationship_id) == {source_id, target_id, "unknown_edge"}
  end

  defp run_migration!(:down) do
    run_migration!(
      @constraint_migration_version,
      @constraint_migration_module,
      "20260713103000_harden_relationship_policy_constraints.exs",
      :down
    )

    run_migration!(
      @typed_migration_version,
      @typed_migration_module,
      "20260713101000_type_graph_relationships.exs",
      :down
    )
  end

  defp run_migration!(:up) do
    run_migration!(
      @typed_migration_version,
      @typed_migration_module,
      "20260713101000_type_graph_relationships.exs",
      :up
    )

    run_migration!(
      @constraint_migration_version,
      @constraint_migration_module,
      "20260713103000_harden_relationship_policy_constraints.exs",
      :up
    )
  end

  defp run_migration!(version, module, filename, direction) do
    path = Application.app_dir(:office_graph, "priv/repo/migrations/#{filename}")
    Code.require_file(path)

    Ecto.Migration.Runner.run(
      Repo,
      Repo.config(),
      version,
      module,
      :forward,
      direction,
      direction,
      log: false
    )
  end

  defp insert_legacy_relationships!(bootstrap, operation) do
    signal_item_id = insert_graph_item!(bootstrap, "signal")
    task_item_id = insert_graph_item!(bootstrap, "task")
    review_finding_item_id = insert_graph_item!(bootstrap, "review_finding")
    verification_check_item_id = insert_graph_item!(bootstrap, "verification_check")
    evidence_item_id = insert_graph_item!(bootstrap, "evidence_item")
    artifact_item_id = insert_graph_item!(bootstrap, "artifact")

    insert_audit!(
      bootstrap,
      operation,
      "task",
      graph_resource_id!(task_item_id),
      "task.create"
    )

    insert_audit!(
      bootstrap,
      operation,
      "review_finding",
      graph_resource_id!(review_finding_item_id),
      "review_finding.create"
    )

    insert_audit!(
      bootstrap,
      operation,
      "verification_check",
      graph_resource_id!(verification_check_item_id),
      "verification_check.create"
    )

    insert_audit!(
      bootstrap,
      operation,
      "evidence_item",
      graph_resource_id!(evidence_item_id),
      "evidence_item.create"
    )

    insert_audit!(
      bootstrap,
      operation,
      "artifact",
      graph_resource_id!(artifact_item_id),
      "artifact.create"
    )

    %{
      signal_item_id: signal_item_id,
      task_item_id: task_item_id,
      review_finding_item_id: review_finding_item_id,
      verification_check_item_id: verification_check_item_id,
      evidence_item_id: evidence_item_id,
      artifact_item_id: artifact_item_id,
      produced_task_relationship_id:
        insert_legacy_relationship!(signal_item_id, task_item_id, "produced_task"),
      review_relationship_id:
        insert_legacy_relationship!(task_item_id, review_finding_item_id, "has_review_finding"),
      check_relationship_id:
        insert_legacy_relationship!(
          review_finding_item_id,
          verification_check_item_id,
          "requires_verification"
        ),
      evidence_relationship_id:
        insert_legacy_relationship!(
          verification_check_item_id,
          evidence_item_id,
          "has_evidence"
        ),
      artifact_relationship_id:
        insert_legacy_relationship!(evidence_item_id, artifact_item_id, "references_artifact")
    }
  end

  defp insert_graph_item!(bootstrap, resource_type) do
    id = Ecto.UUID.generate()
    resource_id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO graph_items (
        id, organization_id, workspace_id, resource_type, resource_id, title, inserted_at, updated_at
      ) VALUES ($1::text::uuid, $2::text::uuid, $3::text::uuid, $4, $5::text::uuid, $6, now(), now())
      """,
      [
        id,
        bootstrap.organization.id,
        bootstrap.workspace.id,
        resource_type,
        resource_id,
        "Legacy #{resource_type}"
      ]
    )

    id
  end

  defp insert_legacy_relationship!(source_item_id, target_item_id, relationship_type) do
    id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO graph_relationships (
        id, source_item_id, target_item_id, relationship_type, inserted_at, updated_at
      ) VALUES ($1::text::uuid, $2::text::uuid, $3::text::uuid, $4, now(), now())
      """,
      [id, source_item_id, target_item_id, relationship_type]
    )

    id
  end

  defp insert_audit!(bootstrap, operation, resource_type, resource_id, action) do
    Repo.query!(
      """
      INSERT INTO audit_records (
        id, operation_id, actor_principal_id, action, resource_type, resource_id,
        sensitive, inserted_at, updated_at
      ) VALUES ($1::text::uuid, $2::text::uuid, $3::text::uuid, $4, $5, $6::text::uuid, true, now(), now())
      """,
      [
        Ecto.UUID.generate(),
        operation.id,
        bootstrap.principal.id,
        action,
        resource_type,
        resource_id
      ]
    )
  end

  defp relationship_by_id!(id) do
    result =
      Repo.query!(
        """
        SELECT
          definitions.key,
          relationships.source_item_id::text,
          relationships.target_item_id::text,
          relationships.organization_id::text,
          relationships.workspace_id::text,
          relationships.lifecycle,
          relationships.asserting_principal_id::text,
          relationships.operation_id::text,
          relationships.valid_from,
          relationships.valid_until
        FROM graph_relationships AS relationships
        JOIN relationship_definitions AS definitions
          ON definitions.id = relationships.definition_id
        WHERE relationships.id = $1::text::uuid
        """,
        [id]
      )

    [
      definition_key,
      source_item_id,
      target_item_id,
      organization_id,
      workspace_id,
      lifecycle,
      asserting_principal_id,
      operation_id,
      valid_from,
      valid_until
    ] = List.first(result.rows)

    %{
      definition_key: definition_key,
      source_item_id: source_item_id,
      target_item_id: target_item_id,
      organization_id: organization_id,
      workspace_id: workspace_id,
      lifecycle: lifecycle,
      asserting_principal_id: asserting_principal_id,
      operation_id: operation_id,
      valid_from: valid_from,
      valid_until: valid_until
    }
  end

  defp legacy_relationship!(id) do
    result =
      Repo.query!(
        """
        SELECT source_item_id::text, target_item_id::text, relationship_type
        FROM graph_relationships
        WHERE id = $1::text::uuid
        """,
        [id]
      )

    result.rows |> List.first() |> List.to_tuple()
  end

  defp graph_resource_id!(graph_item_id) do
    %{rows: [[resource_id]]} =
      Repo.query!("SELECT resource_id::text FROM graph_items WHERE id = $1::text::uuid", [
        graph_item_id
      ])

    resource_id
  end

  defp column_exists?(table, column) do
    %{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM information_schema.columns
          WHERE table_schema = current_schema()
            AND table_name = $1
            AND column_name = $2
        )
        """,
        [table, column]
      )

    exists?
  end

  defp constraint_exists?(constraint) do
    %{rows: [[exists?]]} =
      Repo.query!(
        """
        SELECT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = $1
        )
        """,
        [constraint]
      )

    exists?
  end
end
