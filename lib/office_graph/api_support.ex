defmodule OfficeGraph.ApiSupport do
  @moduledoc """
  Public boundary for shared API context loading and response support.
  """

  use Boundary,
    deps: [
      OfficeGraph.Foundation,
      OfficeGraph.Integrations,
      OfficeGraph.Operations,
      OfficeGraph.ProposedChanges,
      OfficeGraph.Verification,
      OfficeGraph.WorkGraph
    ],
    exports: []

  alias OfficeGraph.Foundation
  alias OfficeGraph.Integrations
  alias OfficeGraph.Operations
  alias OfficeGraph.ProposedChanges
  alias OfficeGraph.Verification
  alias OfficeGraph.WorkGraph

  def submit_manual_intake(params) do
    with {:ok, bootstrap} <- Foundation.bootstrap_local_owner([]),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :manual_intake_submit) do
      Integrations.submit_manual_intake(bootstrap.session, operation, %{
        source_identity: value(params, :source_identity),
        replay_identity: value(params, :replay_identity),
        body: value(params, :body)
      })
    end
  end

  def apply_proposed_changes(params) do
    ids = value(params, :ids) || []

    with {:ok, bootstrap} <- Foundation.bootstrap_local_owner([]),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :proposed_change_apply),
         proposed_changes <- ProposedChanges.get_many!(bootstrap.session, ids) do
      ProposedChanges.apply_all(bootstrap.session, operation, proposed_changes)
    end
  end

  def complete_verification(params) do
    with {:ok, bootstrap} <- Foundation.bootstrap_local_owner([]),
         {:ok, operation} <- Operations.start_operation(bootstrap.session, :evidence_link),
         verification_check <-
           WorkGraph.get_verification_check!(value(params, :verification_check_id)) do
      Verification.complete_with_evidence(bootstrap.session, operation, verification_check, %{
        title: value(params, :title),
        body: value(params, :body),
        artifact_uri: value(params, :artifact_uri)
      })
    end
  end

  defp value(params, key) do
    params[key] || params[to_string(key)]
  end
end
