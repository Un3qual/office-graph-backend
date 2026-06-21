defmodule OfficeGraph.Architecture.AshConformanceTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.Authorization.Checks.HasCapability
  alias OfficeGraph.Identity.SessionContext
  alias OfficeGraph.WorkGraph.Changes.ValidateSameScopeReferences

  @ash_domain OfficeGraph.WorkGraph.Domain
  @ash_domains Application.compile_env(:office_graph, :ash_domains, [])

  @required_resources [
    OfficeGraph.WorkGraph.Resources.Signal,
    OfficeGraph.WorkGraph.Resources.Task,
    OfficeGraph.WorkGraph.Resources.ReviewFinding,
    OfficeGraph.WorkGraph.Resources.VerificationCheck,
    OfficeGraph.WorkGraph.Resources.Artifact,
    OfficeGraph.WorkGraph.Resources.EvidenceItem,
    OfficeGraph.WorkGraph.Resources.VerificationResult
  ]

  @expected_action_capabilities %{
    OfficeGraph.WorkGraph.Resources.Signal => %{
      read: {:read, :skeleton_read},
      create: {:create, :manual_intake_submit}
    },
    OfficeGraph.WorkGraph.Resources.Task => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply},
      mark_verified_complete: {:update, :verification_complete}
    },
    OfficeGraph.WorkGraph.Resources.ReviewFinding => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply},
      mark_verified_complete: {:update, :verification_complete}
    },
    OfficeGraph.WorkGraph.Resources.VerificationCheck => %{
      read: {:read, :skeleton_read},
      create: {:create, :proposed_change_apply},
      mark_satisfied: {:update, :verification_complete}
    },
    OfficeGraph.WorkGraph.Resources.Artifact => %{
      read: {:read, :skeleton_read},
      create: {:create, :evidence_link}
    },
    OfficeGraph.WorkGraph.Resources.EvidenceItem => %{
      read: {:read, :skeleton_read},
      create: {:create, :evidence_link}
    },
    OfficeGraph.WorkGraph.Resources.VerificationResult => %{
      read: {:read, :skeleton_read},
      create: {:create, :verification_complete}
    }
  }

  @expected_reference_validations %{
    OfficeGraph.WorkGraph.Resources.Signal => %{
      create: [
        graph_item_id: OfficeGraph.WorkGraph.GraphItem,
        body_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.Resources.Task => %{
      create: [
        graph_item_id: OfficeGraph.WorkGraph.GraphItem,
        source_signal_id: OfficeGraph.WorkGraph.Signal,
        body_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.Resources.ReviewFinding => %{
      create: [
        graph_item_id: OfficeGraph.WorkGraph.GraphItem,
        task_id: OfficeGraph.WorkGraph.Task,
        body_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.Resources.VerificationCheck => %{
      create: [
        graph_item_id: OfficeGraph.WorkGraph.GraphItem,
        review_finding_id: OfficeGraph.WorkGraph.ReviewFinding,
        description_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.Resources.Artifact => %{
      create: [
        graph_item_id: OfficeGraph.WorkGraph.GraphItem
      ]
    },
    OfficeGraph.WorkGraph.Resources.EvidenceItem => %{
      create: [
        graph_item_id: OfficeGraph.WorkGraph.GraphItem,
        verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
        artifact_id: OfficeGraph.WorkGraph.Artifact,
        body_document_id: OfficeGraph.Content.Document
      ]
    },
    OfficeGraph.WorkGraph.Resources.VerificationResult => %{
      create: [
        verification_check_id: OfficeGraph.WorkGraph.VerificationCheck,
        evidence_item_id: OfficeGraph.WorkGraph.EvidenceItem,
        operation_id: OfficeGraph.Operations.OperationCorrelation
      ]
    }
  }

  @approved_direct_repo_mutation_functions %{
    "lib/office_graph/work_graph.ex" =>
      MapSet.new([
        "graph_transaction/1",
        "insert_graph_item!/5",
        "insert_relationship!/3"
      ]),
    "lib/office_graph/integrations.ex" =>
      MapSet.new(["record_manual_intake/3", "get_or_insert!/3"]),
    "lib/office_graph/operations.ex" => MapSet.new(["start_operation/3"]),
    "lib/office_graph/audit.ex" => MapSet.new(["record!/5"]),
    "lib/office_graph/revisions.ex" => MapSet.new(["record!/5"]),
    "lib/office_graph/identity.ex" =>
      MapSet.new(["ensure_owner/1", "ensure_session_context/3", "get_or_insert!/3"]),
    "lib/office_graph/tenancy.ex" => MapSet.new(["ensure_local_scope/1", "get_or_insert!/3"]),
    "lib/office_graph/authorization.ex" =>
      MapSet.new(["ensure_owner_role/2", "get_or_insert!/3"]),
    "lib/office_graph/proposed_changes.ex" =>
      MapSet.new(["create_for_manual_intake/4", "reject!/2", "mark_applied!/1"]),
    "lib/office_graph/content.ex" => MapSet.new(["create_plain_document/3"])
  }

  test "work graph has an Ash domain and required Ash resources" do
    assert @ash_domain in @ash_domains,
           "#{inspect(@ash_domain)} must be registered in :office_graph, :ash_domains"

    assert Code.ensure_loaded?(@ash_domain),
           "#{inspect(@ash_domain)} is not loaded; define the WorkGraph Ash domain before this conformance test can pass"

    for resource <- @required_resources do
      assert Code.ensure_loaded?(resource),
             "#{inspect(resource)} is not loaded; define the required WorkGraph Ash resource before this conformance test can pass"

      assert Ash.Resource.Info.data_layer(resource) == AshPostgres.DataLayer,
             "#{inspect(resource)} must use AshPostgres.DataLayer"

      refute AshPostgres.DataLayer.Info.migrate?(resource),
             "#{inspect(resource)} must set migrate? false"
    end
  end

  test "work graph Ash domain registers the required resources" do
    assert Code.ensure_loaded?(@ash_domain),
           "#{inspect(@ash_domain)} is not loaded; cannot inspect registered Ash resources"

    registered =
      @ash_domain
      |> Ash.Domain.Info.resources()
      |> MapSet.new()

    missing =
      @required_resources
      |> MapSet.new()
      |> MapSet.difference(registered)
      |> MapSet.to_list()

    assert missing == [],
           "WorkGraph Ash domain is missing required resources: #{inspect(missing)}"
  end

  test "WorkGraph Ash resources expose public actions with explicit capability policies" do
    for resource <- @required_resources do
      for {action_name, {action_type, capability}} <-
            Map.fetch!(@expected_action_capabilities, resource) do
        assert public_action?(resource, action_name, action_type),
               "#{inspect(resource)} must expose public #{action_type} action #{inspect(action_name)}"

        assert capability_policy?(resource, action_name, action_type, capability),
               "#{inspect(resource)} #{inspect(action_name)} must authorize through #{inspect(HasCapability)} with capability #{inspect(capability)}"
      end
    end
  end

  test "WorkGraph Ash read actions include actor scope filter policies" do
    for resource <- @required_resources do
      read_actions = actions_by_type(resource, :read)

      assert read_actions != [],
             "#{inspect(resource)} must define at least one read action"

      for action <- read_actions do
        assert scope_filter_policy?(resource, action.name, :read),
               "#{inspect(resource)} #{inspect(action.name)} must filter reads by actor organization_id and workspace_id"
      end
    end
  end

  test "WorkGraph Ash create actions validate same-scope references" do
    expected_resources = @expected_reference_validations |> Map.keys() |> MapSet.new()

    assert expected_resources == MapSet.new(@required_resources),
           "Expected reference validation table must cover every required resource"

    for resource <- @required_resources do
      expected_by_action = Map.fetch!(@expected_reference_validations, resource)
      create_actions = actions_by_type(resource, :create)

      assert MapSet.new(Enum.map(create_actions, & &1.name)) ==
               MapSet.new(Map.keys(expected_by_action)),
             "#{inspect(resource)} must define exactly the create actions covered by the same-scope reference table"

      for action <- create_actions do
        expected_references = Map.fetch!(expected_by_action, action.name)

        assert same_scope_reference_validation(action) == expected_references,
               "#{inspect(resource)} #{inspect(action.name)} must validate same-scope references #{inspect(expected_references)}"
      end
    end
  end

  test "shared Ash capability check is loadable" do
    assert Code.ensure_loaded?(HasCapability)

    assert HasCapability.describe(capability: :skeleton_read) =~
             "skeleton_read"
  end

  test "shared Ash capability check enforces explicit capability and target scope" do
    organization_id = Ecto.UUID.generate()
    workspace_id = Ecto.UUID.generate()

    actor = session_context(organization_id, workspace_id, ["skeleton.read"])
    changeset = scoped_changeset(organization_id, workspace_id)

    assert HasCapability.match?(actor, %{changeset: changeset}, capability: :skeleton_read)

    refute HasCapability.match?(actor, %{changeset: changeset}, [])

    refute HasCapability.match?(nil, %{changeset: changeset}, capability: :skeleton_read)

    refute HasCapability.match?(
             actor,
             %{changeset: scoped_changeset(Ecto.UUID.generate(), workspace_id)},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             actor,
             %{changeset: scoped_changeset(organization_id, Ecto.UUID.generate())},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             actor,
             %{changeset: %Ash.Changeset{}},
             capability: :skeleton_read
           )

    refute HasCapability.match?(
             session_context(organization_id, workspace_id, []),
             %{changeset: changeset},
             capability: :skeleton_read
           )

    assert HasCapability.match?(
             actor,
             %{query: %Ash.Query{}, action: %{type: :read}},
             capability: :skeleton_read
           )

    assert HasCapability.match?(
             session_context(organization_id, workspace_id, ["verification.complete"]),
             %{
               changeset: %Ash.Changeset{
                 action_type: :update,
                 data: %{organization_id: organization_id, workspace_id: workspace_id},
                 attributes: %{
                   organization_id: Ecto.UUID.generate(),
                   workspace_id: Ecto.UUID.generate()
                 }
               }
             },
             capability: :verification_complete
           )
  end

  test "direct Repo mutation paths are explicitly allowlisted" do
    unapproved =
      Enum.reject(direct_repo_mutations(), fn mutation ->
        mutation.function in Map.get(
          @approved_direct_repo_mutation_functions,
          mutation.path,
          MapSet.new()
        )
      end)

    assert unapproved == [],
           "Found direct Repo/Ecto.Multi mutations outside approved functions:\n#{inspect(unapproved, pretty: true)}"
  end

  defp direct_repo_mutations do
    mutation_pattern =
      ~r/((?:OfficeGraph\.)?Repo\.(insert!?|insert_all|update!?|update_all|delete!?|delete_all|insert_or_update!|insert_or_update|transaction)\b|(?:Ecto\.)?Multi\.(insert|insert_all|update|update_all|delete|delete_all|insert_or_update!|insert_or_update)\b)/

    "lib/office_graph/**/*.ex"
    |> Path.wildcard()
    |> Enum.flat_map(fn path -> scan_file_for_mutations(path, mutation_pattern) end)
  end

  defp public_action?(resource, action_name, action_type) do
    resource
    |> Ash.Resource.Info.public_actions()
    |> Enum.any?(&(&1.name == action_name and &1.type == action_type))
  end

  defp actions_by_type(resource, action_type) do
    resource
    |> Ash.Resource.Info.actions()
    |> Enum.filter(&(&1.type == action_type))
  end

  defp capability_policy?(resource, action_name, action_type, capability) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.filter(&policy_applies_to_action?(&1, action_name, action_type))
    |> Enum.any?(&policy_has_capability?(&1, capability))
  end

  defp scope_filter_policy?(resource, action_name, action_type) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.filter(&policy_applies_to_action?(&1, action_name, action_type))
    |> Enum.any?(&policy_has_scope_filter?/1)
  end

  defp policy_applies_to_action?(
         %Ash.Policy.Policy{condition: conditions},
         action_name,
         action_type
       ) do
    Enum.any?(List.wrap(conditions), fn
      {Ash.Policy.Check.Action, opts} ->
        action_name in Keyword.fetch!(opts, :action)

      {Ash.Policy.Check.ActionType, opts} ->
        action_type in Keyword.fetch!(opts, :type)

      _condition ->
        false
    end)
  end

  defp policy_has_capability?(%Ash.Policy.Policy{policies: checks}, capability) do
    Enum.any?(List.wrap(checks), fn
      %Ash.Policy.Check{
        check_module: HasCapability,
        check_opts: opts,
        type: :authorize_if
      } ->
        Keyword.fetch(opts, :capability) == {:ok, capability}

      _check ->
        false
    end)
  end

  defp policy_has_scope_filter?(%Ash.Policy.Policy{policies: checks}) do
    Enum.any?(List.wrap(checks), fn
      %Ash.Policy.Check{
        check_module: Ash.Policy.Check.Expression,
        check_opts: opts,
        type: :authorize_if
      } ->
        opts
        |> Keyword.get(:expr)
        |> scope_filter_expression?()

      _check ->
        false
    end)
  end

  defp scope_filter_expression?(%Ash.Query.BooleanExpression{
         op: :and,
         left: left,
         right: right
       }) do
    [scope_actor_equality_field(left), scope_actor_equality_field(right)]
    |> MapSet.new()
    |> MapSet.equal?(MapSet.new([:organization_id, :workspace_id]))
  end

  defp scope_filter_expression?(_expression), do: false

  defp scope_actor_equality_field(%Ash.Query.Call{
         name: :==,
         args: [%Ash.Query.Ref{attribute: left_field}, {:_actor, right_field}]
       })
       when left_field == right_field and left_field in [:organization_id, :workspace_id],
       do: left_field

  defp scope_actor_equality_field(%Ash.Query.Call{
         name: :==,
         args: [{:_actor, left_field}, %Ash.Query.Ref{attribute: right_field}]
       })
       when left_field == right_field and left_field in [:organization_id, :workspace_id],
       do: left_field

  defp scope_actor_equality_field(_expression), do: nil

  defp same_scope_reference_validation(%{changes: changes}) do
    Enum.find_value(changes, fn
      %Ash.Resource.Change{change: {ValidateSameScopeReferences, opts}} ->
        Keyword.fetch!(opts, :references)

      _change ->
        nil
    end)
  end

  defp session_context(organization_id, workspace_id, capabilities) do
    %SessionContext{
      principal_id: Ecto.UUID.generate(),
      session_id: Ecto.UUID.generate(),
      organization_id: organization_id,
      workspace_id: workspace_id,
      capabilities: MapSet.new(capabilities)
    }
  end

  defp scoped_changeset(organization_id, workspace_id) do
    %Ash.Changeset{
      attributes: %{
        organization_id: organization_id,
        workspace_id: workspace_id
      }
    }
  end

  defp scan_file_for_mutations(path, mutation_pattern) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce({nil, []}, fn {line, line_number}, {current_function, matches} ->
      current_function = function_name(line) || current_function

      if String.match?(line, mutation_pattern) do
        mutation = %{
          path: path,
          line: line_number,
          function: current_function,
          source: String.trim(line)
        }

        {current_function, [mutation | matches]}
      else
        {current_function, matches}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp function_name(line) do
    case Regex.run(~r/^\s*defp?\s+([a-zA-Z0-9_!?]+)\((.*)\)\s+do/, line) do
      [_, name, args] -> "#{name}/#{arity(args)}"
      _ -> nil
    end
  end

  defp arity(args) do
    args
    |> String.trim()
    |> case do
      "" -> 0
      args -> args |> String.split(",") |> length()
    end
  end
end
