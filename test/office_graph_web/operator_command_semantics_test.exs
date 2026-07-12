defmodule OfficeGraphWeb.OperatorCommandSemanticsTest do
  use OfficeGraphWeb.ConnCase, async: true

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
  end

  describe "shared public error semantics" do
    test "table-drives GraphQL and JSON parity across public command outcomes" do
      id = Ecto.UUID.generate()

      cases = [
        {:forbidden, :authorization, "forbidden", "The action is not authorized.", %{}, 403},
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
        {{:missing_verification_check, id}, :validation, "missing_verification_check",
         "A verification check could not be found.", %{verification_check_id: id}, 422},
        {{:invalid_evidence_result, "passsed"}, :validation, "invalid_evidence_result",
         "The evidence result is not supported.", %{evidence_result: "passsed"}, 422},
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

    test "recursively sanitizes nested unsafe reasons for both transports" do
      unsafe_reason =
        {:normalized_event_operation_mismatch,
         %{
           {:sql, :key} => "SELECT hidden FROM adapter_state",
           safe: [:missing_normalized_event_id, "event-123"],
           exception: %RuntimeError{message: "SELECT secret FROM credentials"},
           adapter: {:adapter_error, "Postgrex SQL connection details"},
           adapter_token: "Postgrex.Error",
           exception_token: "Ecto.ConstraintError",
           sql_token: "SELECT"
         }}

      error = {:invalid_proposed_change_set, unsafe_reason}
      assert {:error, graphql_error} = GraphQLErrors.to_absinthe(error)
      json_conn = JsonErrors.render(build_conn(), error)
      serialized = inspect([graphql_error, json_response(json_conn, 409)])

      refute serialized =~ "SELECT"
      refute serialized =~ "credentials"
      refute serialized =~ "Postgrex"
      refute serialized =~ "RuntimeError"

      classification = Errors.classify(error)

      assert classification.metadata == %{
               reason: %{
                 kind: "normalized_event_operation_mismatch",
                 value: %{
                   "adapter" => %{kind: "internal", value: "invalid"},
                   "adapter_token" => "invalid",
                   "exception" => "invalid",
                   "exception_token" => "invalid",
                   "invalid" => "invalid",
                   "safe" => ["missing_normalized_event_id", "event-123"],
                   "sql_token" => "invalid"
                 }
               }
             }
    end
  end

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), stringify_keys(nested)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
