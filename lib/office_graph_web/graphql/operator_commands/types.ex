defmodule OfficeGraphWeb.GraphQL.OperatorCommands.Types do
  use Absinthe.Schema.Notation

  input_object :github_installation_permission_input do
    field :name, non_null(:string)
    field :access_level, non_null(:string)
  end

  input_object :bind_github_installation_input do
    field :idempotency_key, non_null(:string)
    field :workspace_id, :id
    field :external_installation_id, non_null(:string)
    field :app_slug, non_null(:string)
    field :account_login, non_null(:string)
    field :account_type, non_null(:string)
    field :service_principal_email, non_null(:string)
    field :webhook_principal_email, non_null(:string)
    field :webhook_secret_reference, non_null(:string)
    field :app_private_key_reference, non_null(:string)
    field :permissions, non_null(list_of(non_null(:github_installation_permission_input)))
  end

  object :github_installation_command_result do
    field :id, non_null(:id)
    field :organization_id, non_null(:id)
    field :workspace_id, :id
    field :external_installation_id, non_null(:string)
    field :lifecycle_state, non_null(:string)
    field :service_principal_id, non_null(:id)
    field :webhook_principal_id, non_null(:id)
  end

  object :github_permission_snapshot_command_result do
    field :id, non_null(:id)
    field :version, non_null(:integer)
  end

  object :github_permission_command_result do
    field :name, non_null(:string)
    field :access_level, non_null(:string)
  end

  object :github_credential_command_result do
    field :id, non_null(:id)
    field :purpose, non_null(:string)
    field :kind, non_null(:string)
    field :status, non_null(:string)
  end

  object :bind_github_installation_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :installation, non_null(:github_installation_command_result)
    field :permission_snapshot, non_null(:github_permission_snapshot_command_result)
    field :permissions, non_null(list_of(non_null(:github_permission_command_result)))
    field :credentials, non_null(list_of(non_null(:github_credential_command_result)))
  end

  input_object :reply_to_github_review_input do
    field :idempotency_key, non_null(:string)
    field :installation_id, non_null(:id)
    field :review_comment_id, non_null(:id)
    field :body, non_null(:string)
    field :expected_provider_version, non_null(:string)
  end

  input_object :update_github_check_input do
    field :idempotency_key, non_null(:string)
    field :installation_id, non_null(:id)
    field :check_run_id, non_null(:id)
    field :status, non_null(:string)
    field :conclusion, :string
    field :details_url, non_null(:string)
    field :expected_provider_version, non_null(:string)
  end

  object :github_outbound_action_command_result do
    field :id, non_null(:id)
    field :installation_id, non_null(:id)
    field :action_kind, non_null(:string)
    field :target_type, non_null(:string)
    field :target_id, non_null(:id)
    field :expected_provider_version, non_null(:string)
    field :state, non_null(:string)
    field :provider_response_id, :string
    field :provider_response_version, :string
    field :failure_class, :string
    field :failure_code, :string
  end

  object :github_outbound_action_payload do
    field :command, non_null(:string)
    field :operation_id, non_null(:id)
    field :affected_ids, non_null(list_of(non_null(:operator_typed_id)))
    field :action, non_null(:github_outbound_action_command_result)
  end
end
