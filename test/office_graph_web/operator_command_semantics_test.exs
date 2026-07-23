defmodule OfficeGraphWeb.OperatorCommandSemanticsTest do
  use OfficeGraphWeb.ConnCase, async: true

  defmodule SafeReason do
    defstruct [:id, :state, :details]
  end

  alias OfficeGraphWeb.GraphQL.Common.Errors, as: GraphQLErrors
  alias OfficeGraphWeb.JsonApi.Common.Errors, as: JsonErrors
  alias OfficeGraphWeb.OperatorCommands.{Errors, Input}

  describe "shared command input" do
    test "preserves raw strings while trimming ordinary strings" do
      assert {:ok,
              %{
                idempotency_key: "intake-key",
                source_identity: "manual:test",
                replay_identity: "paste:test",
                body: "\n  pasted body  \n"
              }} =
               Input.parse(:submit_manual_intake, %{
                 "idempotency_key" => "  intake-key  ",
                 "source_identity" => "  manual:test  ",
                 "replay_identity" => " paste:test ",
                 "body" => "\n  pasted body  \n"
               })
    end

    test "casts UUID lists and reports stable field errors" do
      event_id = Ecto.UUID.generate()
      proposed_change_id = Ecto.UUID.generate()

      assert {:ok,
              %{
                idempotency_key: "apply-key",
                normalized_event_id: ^event_id,
                proposed_change_ids: [^proposed_change_id]
              }} =
               Input.parse(:apply_proposed_changes, %{
                 idempotency_key: "apply-key",
                 normalized_event_id: event_id,
                 proposed_change_ids: [proposed_change_id]
               })

      assert {:error, {:missing_field, :normalized_event_id}} =
               Input.parse(:apply_proposed_changes, %{
                 idempotency_key: "apply-key",
                 proposed_change_ids: [proposed_change_id]
               })

      assert {:error, {:invalid_field, :proposed_change_ids}} =
               Input.parse(:apply_proposed_changes, %{
                 idempotency_key: "apply-key",
                 normalized_event_id: event_id,
                 proposed_change_ids: ["not-a-uuid"]
               })
    end

    test "atom keys take precedence over string keys even for false and nil values" do
      common = %{
        "idempotency_key" => "string-key",
        "source_identity" => "manual:string",
        "replay_identity" => "paste:string",
        "body" => "string body"
      }

      assert {:error, {:invalid_field, :idempotency_key}} =
               Input.parse(:submit_manual_intake, Map.put(common, :idempotency_key, false))

      assert {:error, {:missing_field, :source_identity}} =
               Input.parse(:submit_manual_intake, Map.put(common, :source_identity, nil))

      assert {:ok, %{replay_identity: "paste:atom"}} =
               Input.parse(:submit_manual_intake, Map.put(common, :replay_identity, "paste:atom"))
    end
  end

  describe "shared public error semantics" do
    test "table-drives GraphQL and JSON parity across public command outcomes" do
      id = Ecto.UUID.generate()

      cases = [
        {:forbidden, :authorization, "forbidden", "The action is not authorized.", %{}, 403},
        {:integration_storage_unavailable, :availability, "integration_storage_unavailable",
         "Integration storage is temporarily unavailable.", %{}, 503},
        {{:missing_proposed_change, id}, :validation, "missing_proposed_change",
         "A proposed change could not be found.", %{proposed_change_id: id}, 422},
        {{:invalid_proposed_change_status, id}, :conflict, "invalid_proposed_change_status",
         "A proposed change is no longer pending.", %{proposed_change_id: id}, 409},
        {{:invalid_proposed_change, id}, :validation, "invalid_proposed_change",
         "A proposed change failed validation.", %{proposed_change_id: id}, 422},
        {{:invalid_proposed_change_set, :missing_normalized_event_id}, :conflict,
         "invalid_proposed_change_set", "The proposed change set is invalid.",
         %{reason: "missing_normalized_event_id"}, 409},
        {{:invalid_proposed_change_replay, :missing_applied_resource}, :validation,
         "invalid_proposed_change_replay", "The applied proposal result is unavailable.", %{},
         422},
        {{:manual_intake_replay_conflict, id}, :conflict, "manual_intake_replay_conflict",
         "Manual intake replay identity conflicts with an accepted event.", %{accepted_id: id},
         409},
        {{:command_idempotency_conflict, id}, :conflict, "idempotency_conflict",
         "The idempotency key conflicts with different command input.", %{operation_id: id}, 409},
        {{:stale_packet_version, id, id}, :conflict, "stale_packet_version",
         "The work packet version is stale.", %{packet_id: id, current_version_id: id}, 409},
        {{:active_work_run, id, id}, :conflict, "active_work_run",
         "The packet version already has an active work run.",
         %{packet_version_id: id, run_id: id}, 409},
        {{:stale_work_run_state, id, "running", "pending"}, :conflict, "stale_run_state",
         "The work run state is stale.",
         %{run_id: id, execution_state: "running", verification_state: "pending"}, 409},
        {{:stale_agent_execution, id, 2}, :conflict, "stale_agent_execution",
         "The agent execution version is stale.", %{execution_id: id, current_version: 2}, 409},
        {{:agent_execution_terminal, id, "cancelled"}, :conflict, "agent_execution_terminal",
         "The agent execution is already terminal.",
         %{execution_id: id, execution_state: "cancelled"}, 409},
        {{:missing_verification_check, id}, :validation, "missing_verification_check",
         "A verification check could not be found.", %{verification_check_id: id}, 422},
        {{:invalid_evidence_result, "passsed"}, :validation, "invalid_evidence_result",
         "The evidence result is not supported.", %{evidence_result: "invalid"}, 422},
        {{:observation_idempotency_conflict, id}, :conflict, "idempotency_conflict",
         "The observation source idempotency key conflicts with different input.",
         %{observation_id: id}, 409},
        {{:invalid_verification_check_status, id}, :conflict, "invalid_verification_check_status",
         "A verification check is no longer required.", %{verification_check_id: id}, 409},
        {{:packet_version_not_ready, id}, :validation, "packet_version_not_ready",
         "The packet version is not ready for execution.", %{packet_version_id: id}, 422},
        {{:evidence_candidate_already_accepted, id}, :conflict,
         "evidence_candidate_already_accepted", "The evidence candidate was already accepted.",
         %{evidence_candidate_id: id}, 409},
        {{:verification_result_slot_conflict, id, id}, :conflict,
         "verification_result_slot_conflict",
         "The verification result slot was already completed.",
         %{run_id: id, verification_check_id: id}, 409},
        {{:not_found, :resource, id}, :not_found, "not_found",
         "A referenced record could not be found.", %{id: id}, 422},
        {{:missing_normalized_intake_event, id}, :not_found, "not_found",
         "The operator workflow item could not be found.", %{normalized_event_id: id}, 404},
        {{:missing_field, :body}, :validation, "validation_failed",
         "A required field is missing.", %{field: "body"}, 422},
        {{:invalid_field, :body}, :validation, "validation_failed",
         "A field has an invalid value.", %{field: "body"}, 422}
      ]

      for {error, _category, code, detail, metadata, status} <- cases do
        assert {:error, graphql_error} = GraphQLErrors.to_absinthe(error)
        assert graphql_error[:message] == detail

        graphql_extensions = stringify_keys(graphql_error[:extensions])
        assert graphql_extensions["code"] == code
        assert Map.drop(graphql_extensions, ["code"]) == stringify_keys(metadata)

        json_conn = JsonErrors.render(build_conn(), error)
        assert json_conn.status == status
        json_error = json_response(json_conn, status)["error"]
        assert json_error["code"] == code
        assert json_error["detail"] == detail
        assert Map.drop(json_error, ["code", "detail"]) == stringify_keys(metadata)
      end

      for {error, category, code, detail, metadata, _status} <- cases do
        assert %{category: ^category, code: ^code, detail: ^detail, metadata: ^metadata} =
                 Errors.classify(error)
      end
    end

    test "compact unknown values and keys fail closed under registered reason contexts" do
      id = Ecto.UUID.generate()

      compact_bypasses = [
        "adaptertimeout",
        "databasecredentials",
        "runtimefailure",
        "sqlstate23505",
        "selectcredentials",
        "officegraphrepo"
      ]

      unsafe_reason =
        {:normalized_event_operation_mismatch,
         Map.new(compact_bypasses, fn token -> {token, token} end)
         |> Map.put(:safe_id, id)
         |> Map.put({:unsafe, :key}, id)}

      error = {:invalid_proposed_change_set, unsafe_reason}
      assert {:error, graphql_error} = GraphQLErrors.to_absinthe(error)
      json_conn = JsonErrors.render(build_conn(), error)
      serialized = inspect([graphql_error, json_response(json_conn, 409)])

      for token <- compact_bypasses do
        refute serialized =~ token
      end

      assert Errors.classify(error).metadata == %{
               reason: %{
                 kind: "normalized_event_operation_mismatch",
                 value: "invalid"
               }
             }
    end

    test "registered proposal reasons preserve only their exact public value shapes" do
      first_id = Ecto.UUID.generate()
      second_id = Ecto.UUID.generate()

      cases = [
        {:missing_normalized_event_id, "missing_normalized_event_id"},
        {{:normalized_event_operation_mismatch, first_id},
         %{kind: "normalized_event_operation_mismatch", value: first_id}},
        {{:normalized_event_not_accepted, first_id},
         %{kind: "normalized_event_not_accepted", value: first_id}},
        {{:normalized_event_mismatch, first_id},
         %{kind: "normalized_event_mismatch", value: first_id}},
        {{:mixed_normalized_event_ids, [first_id, second_id]},
         %{kind: "mixed_normalized_event_ids", value: [first_id, second_id]}},
        {{:duplicate_change_type, "create_signal"},
         %{kind: "duplicate_change_type", value: "create_signal"}},
        {{:missing_change_type, "create_task"},
         %{kind: "missing_change_type", value: "create_task"}},
        {{:unexpected_change_type, "adaptertimeout"},
         %{kind: "unexpected_change_type", value: "invalid"}},
        {{:normalized_event_lookup_failed, %RuntimeError{message: "databasecredentials"}},
         %{kind: "normalized_event_lookup_failed", value: "invalid"}}
      ]

      for {reason, expected} <- cases do
        error = {:invalid_proposed_change_set, reason}
        assert %{metadata: %{reason: ^expected}} = Errors.classify(error)

        assert_adapter_error(
          error,
          409,
          "invalid_proposed_change_set",
          "The proposed change set is invalid.",
          %{reason: expected}
        )
      end
    end

    test "canonical UUID metadata is version-agnostic while malformed ids fail closed" do
      version_seven_id = "019f579b-957f-7143-bb93-6a56051f6602"

      assert_adapter_error(
        {:missing_proposed_change, version_seven_id},
        422,
        "missing_proposed_change",
        "A proposed change could not be found.",
        %{proposed_change_id: version_seven_id}
      )

      assert_adapter_error(
        {:missing_proposed_change, "officegraphrepo"},
        422,
        "missing_proposed_change",
        "A proposed change could not be found.",
        %{proposed_change_id: "invalid"}
      )
    end

    test "unknown tuple, map, list, and ordinary or exception struct reasons are total and invalid" do
      id = Ecto.UUID.generate()

      reasons = [
        42,
        3.14,
        true,
        false,
        nil,
        {id, :pending, "adaptertimeout"},
        %{id: id, state: :pending},
        [id, :pending],
        %SafeReason{id: id, state: :pending, details: %{field_name: "title"}},
        %RuntimeError{message: "databasecredentials"}
      ]

      for reason <- reasons do
        error = {:invalid_proposed_change_set, reason}
        assert %{metadata: %{reason: "invalid"}} = Errors.classify(error)

        assert_adapter_error(
          error,
          409,
          "invalid_proposed_change_set",
          "The proposed change set is invalid.",
          %{reason: "invalid"}
        )
      end
    end

    test "field conversion is total and adapters preserve classified fields" do
      fields = [
        %{field: "title", message: "is invalid"},
        %{field: "invalid", message: "is invalid"}
      ]

      changeset = %Ash.Changeset{errors: [%{field: :title}, %{field: {:unsafe, :field}}]}

      assert %{fields: ^fields, metadata: %{}} = Errors.classify(changeset)

      assert_adapter_error(changeset, 422, "validation_failed", "Validation failed.", %{
        fields: fields
      })

      malformed = {:invalid_field, {:unsafe, :field}}

      assert %{fields: [%{field: "invalid", message: "A field has an invalid value."}]} =
               Errors.classify(malformed)

      assert_adapter_error(
        malformed,
        422,
        "validation_failed",
        "A field has an invalid value.",
        %{field: "invalid"}
      )

      for compact <-
            ~w(adaptertimeout databasecredentials runtimefailure sqlstate23505 selectcredentials officegraphrepo) do
        assert_adapter_error(
          {:invalid_field, compact},
          422,
          "validation_failed",
          "A field has an invalid value.",
          %{field: "invalid"}
        )
      end
    end

    test "wrapped Ash validation errors preserve every safe field without exposing details" do
      error = %Ash.Error.Invalid{
        errors: [
          %Ash.Error.Changes.InvalidAttribute{
            field: :title,
            message: "SELECT credentials FROM secrets",
            value: "databasecredentials",
            has_value?: true
          },
          %Ash.Error.Invalid{
            errors: [
              %Ash.Error.Changes.Required{
                field: :body,
                type: :attribute,
                resource: OfficeGraph.WorkGraph.Signal
              },
              %Ash.Error.Changes.InvalidChanges{
                fields: [:requirements, {:unsafe, :field}],
                message: "adaptertimeout",
                value: %{token: "must-not-leak"}
              }
            ]
          }
        ]
      }

      fields = [
        %{field: "title", message: "is invalid"},
        %{field: "body", message: "is invalid"},
        %{field: "requirements", message: "is invalid"},
        %{field: "invalid", message: "is invalid"}
      ]

      assert %{fields: ^fields, metadata: %{}} = Errors.classify(error)

      assert_adapter_error(error, 422, "validation_failed", "Validation failed.", %{
        fields: fields
      })

      rendered = inspect(Errors.classify(error))
      refute rendered =~ "credentials"
      refute rendered =~ "adaptertimeout"
      refute rendered =~ "must-not-leak"
    end

    test "nested forbidden and generic fallback retain adapter parity without unsafe fields" do
      nested_forbidden = %{errors: [%{errors: [struct(Ash.Error.Forbidden)]}]}

      assert_adapter_error(
        nested_forbidden,
        403,
        "forbidden",
        "The action is not authorized.",
        %{}
      )

      generic = %RuntimeError{message: "SELECT credentials FROM secrets"}
      assert_adapter_error(generic, 422, "validation_failed", "Validation failed.", %{})
    end

    test "malformed changeset and nested error containers are total" do
      malformed_changeset = %Ash.Changeset{errors: :invalid}

      assert %{fields: [], metadata: %{}} = Errors.classify(malformed_changeset)

      assert_adapter_error(
        malformed_changeset,
        422,
        "validation_failed",
        "Validation failed.",
        %{}
      )

      improper_changeset = %Ash.Changeset{errors: [%{field: :title} | :invalid]}
      retained_field = [%{field: "title", message: "is invalid"}]
      assert %{fields: ^retained_field} = Errors.classify(improper_changeset)

      assert_adapter_error(
        improper_changeset,
        422,
        "validation_failed",
        "Validation failed.",
        %{fields: retained_field}
      )

      nested_forbidden = %{errors: [struct(Ash.Error.Forbidden) | :invalid]}

      assert_adapter_error(
        nested_forbidden,
        403,
        "forbidden",
        "The action is not authorized.",
        %{}
      )

      assert_adapter_error(
        %{errors: :invalid},
        422,
        "validation_failed",
        "Validation failed.",
        %{}
      )
    end
  end

  defp assert_adapter_error(error, status, code, detail, extra) do
    assert {:error, graphql_error} = GraphQLErrors.to_absinthe(error)
    assert graphql_error[:message] == detail

    assert stringify_keys(graphql_error[:extensions]) ==
             stringify_keys(Map.put(extra, :code, code))

    json_conn = JsonErrors.render(build_conn(), error)
    assert json_conn.status == status

    assert json_response(json_conn, status)["error"] ==
             stringify_keys(extra |> Map.put(:code, code) |> Map.put(:detail, detail))
  end

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), stringify_keys(nested)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
