defmodule OfficeGraph.WorkGraph.EvidenceReferenceConcurrencyTest do
  use OfficeGraph.TestSupport.ConcurrencySupport

  alias OfficeGraph.WorkGraph.{Artifact, EvidenceCandidate, GraphItem}

  require Ash.Query

  test "changed candidate inputs on one concurrent operation produce one typed loser" do
    suffix = System.unique_integer([:positive])
    organization_slug = "evidence-candidate-operation-conflict-#{suffix}"
    owner_email = "evidence-candidate-operation-conflict-#{suffix}@office-graph.local"

    try do
      {context, operation} =
        with_unboxed_connection(fn ->
          context = create_candidate_context!(suffix, organization_slug, owner_email)

          {:ok, operation} =
            Operations.start_operation(context.bootstrap.session, :evidence_candidate_create,
              idempotency_key: "evidence-candidate-operation-conflict-#{suffix}"
            )

          {context, operation}
        end)

      first_attrs =
        candidate_attrs(
          context,
          "operation-conflict-#{suffix}",
          "First concurrent candidate claim."
        )

      second_attrs =
        candidate_attrs(
          context,
          "operation-conflict-changed-#{suffix}",
          "Second concurrent candidate claim."
        )

      results =
        [first_attrs, second_attrs]
        |> Enum.map(fn attrs ->
          fn ->
            Verification.create_evidence_candidate(
              context.bootstrap.session,
              operation,
              attrs
            )
          end
        end)
        |> run_concurrently()

      assert [winner] = for({:ok, candidate} <- results, do: candidate)

      assert [winner.id] ==
               for(
                 {:error, {:evidence_candidate_operation_conflict, candidate_id}} <- results,
                 do: candidate_id
               )

      with_unboxed_connection(fn ->
        assert [persisted] = candidates_for_operation(operation.id)
        assert persisted.id == winner.id
      end)
    after
      cleanup_scope(organization_slug, owner_email)
    end
  end

  test "concurrent candidate validation rejects cross-workspace references independently" do
    suffix = System.unique_integer([:positive])
    organization_slug = "evidence-candidate-scope-#{suffix}"
    owner_email = "evidence-candidate-scope-#{suffix}@office-graph.local"

    try do
      {context, valid_operation, invalid_operation, foreign_artifact} =
        with_unboxed_connection(fn ->
          context = create_candidate_context!(suffix, organization_slug, owner_email)

          {:ok, foreign_scope} =
            Foundation.bootstrap_local_owner(
              organization_name: context.bootstrap.organization.name,
              organization_slug: organization_slug,
              workspace_name: "Foreign Evidence Candidate Workspace #{suffix}",
              workspace_slug: "foreign-evidence-candidate-workspace-#{suffix}",
              owner_email: owner_email
            )

          {:ok, valid_operation} =
            Operations.start_operation(context.bootstrap.session, :evidence_candidate_create,
              idempotency_key: "evidence-candidate-scope-valid-#{suffix}"
            )

          {:ok, invalid_operation} =
            Operations.start_operation(context.bootstrap.session, :evidence_candidate_create,
              idempotency_key: "evidence-candidate-scope-invalid-#{suffix}"
            )

          foreign_artifact =
            insert_artifact!(foreign_scope, "Foreign candidate artifact #{suffix}")

          {context, valid_operation, invalid_operation, foreign_artifact}
        end)

      valid_attrs =
        candidate_attrs(context, "scope-valid-#{suffix}", "Valid concurrent candidate.")

      invalid_attrs =
        context
        |> candidate_attrs("scope-invalid-#{suffix}", "Cross-workspace concurrent candidate.")
        |> Map.put(:artifact_id, foreign_artifact.id)

      assert [{:ok, valid_candidate}, {:error, :forbidden}] =
               run_concurrently([
                 fn ->
                   Verification.create_evidence_candidate(
                     context.bootstrap.session,
                     valid_operation,
                     valid_attrs
                   )
                 end,
                 fn ->
                   Verification.create_evidence_candidate(
                     context.bootstrap.session,
                     invalid_operation,
                     invalid_attrs
                   )
                 end
               ])

      with_unboxed_connection(fn ->
        assert [persisted] = candidates_for_operation(valid_operation.id)
        assert persisted.id == valid_candidate.id
        assert candidates_for_operation(invalid_operation.id) == []
      end)
    after
      cleanup_scope(organization_slug, owner_email)
    end
  end

  defp create_candidate_context!(suffix, organization_slug, owner_email) do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_name: "Evidence Candidate Concurrency #{suffix}",
        organization_slug: organization_slug,
        workspace_name: "Evidence Candidate Concurrency Workspace #{suffix}",
        workspace_slug: "evidence-candidate-concurrency-workspace-#{suffix}",
        owner_email: owner_email
      )

    {:ok, verification_check} =
      create_concurrency_verification_check(bootstrap.session, "candidate-reference-#{suffix}")

    {:ok, run_result} =
      create_concurrency_ready_run(
        bootstrap.session,
        [verification_check],
        "candidate-reference-#{suffix}"
      )

    {:ok, observation_result} =
      record_concurrency_observation(
        bootstrap.session,
        run_result.run,
        verification_check,
        "candidate-reference-#{suffix}"
      )

    %{
      bootstrap: bootstrap,
      verification_check: verification_check,
      run: run_result.run,
      observation: observation_result.observation
    }
  end

  defp candidate_attrs(context, key, claim) do
    %{
      work_run_id: context.run.id,
      verification_check_id: context.verification_check.id,
      execution_observation_id: context.observation.id,
      claim: claim,
      source_kind: "provider_check",
      source_identity: "provider:evidence-candidate-#{key}",
      freshness_state: "fresh",
      trust_basis: "signed_provider_payload",
      sensitivity: "internal"
    }
  end

  defp candidates_for_operation(operation_id) do
    EvidenceCandidate
    |> Ash.Query.filter(operation_id == ^operation_id)
    |> Ash.read!(authorize?: false)
  end

  defp insert_artifact!(bootstrap, title) do
    artifact_id = Ecto.UUID.generate()

    graph_item =
      Ash.create!(
        GraphItem,
        %{
          id: Ecto.UUID.generate(),
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          resource_type: "artifact",
          resource_id: artifact_id,
          title: "#{title} graph item"
        },
        action: :create,
        authorize?: false
      )

    Ash.create!(
      Artifact,
      %{
        id: artifact_id,
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        graph_item_id: graph_item.id,
        title: title,
        uri: "https://example.test/#{artifact_id}"
      },
      action: :create,
      actor: bootstrap.session
    )
  end

  defp cleanup_scope(organization_slug, owner_email) do
    with_unboxed_connection(fn ->
      cleanup_work_run_verification_scope!(organization_slug)
      cleanup_bootstrap_scope!(organization_slug, owner_email)
    end)
  end
end
