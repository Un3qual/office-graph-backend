defmodule OfficeGraph.EnterpriseIdentity.WorkOSWebhookReceiptTest do
  use OfficeGraph.DataCase, async: false
  use Oban.Testing, repo: OfficeGraph.Repo

  alias OfficeGraph.{Authorization, EnterpriseIdentity, Foundation, Identity, Operations}

  alias OfficeGraph.EnterpriseIdentity.{
    Directory,
    DirectorySyncEvent,
    DirectoryUser,
    EnterpriseConnection,
    Workers.DirectorySyncWorker
  }

  alias OfficeGraph.Integrations.RawArchive
  alias OfficeGraph.Operations.OperationCorrelation

  require Ash.Query

  @secret_reference "test-secret://workos/webhook"
  @secret "workos-webhook-test-secret"

  defmodule SecretStore do
    @behaviour OfficeGraph.EnterpriseIdentity.SecretStore

    @impl true
    def resolve("test-secret://workos/webhook"), do: {:ok, "workos-webhook-test-secret"}
    def resolve(_reference), do: {:error, :secret_not_found}
  end

  setup do
    original_config = Application.get_env(:office_graph, :workos_enterprise)
    original_store = Application.get_env(:office_graph, :workos_secret_store)

    Application.put_env(:office_graph, :workos_enterprise,
      webhook_secret_reference: @secret_reference
    )

    Application.put_env(:office_graph, :workos_secret_store, SecretStore)

    on_exit(fn ->
      restore_env(:workos_enterprise, original_config)
      restore_env(:workos_secret_store, original_store)
    end)

    :ok
  end

  test "valid delivery archives, records, and enqueues exactly once" do
    context = enterprise_context("accepted")
    body = user_body("event_accepted", context.directory.provider_directory_id)
    headers = signed_headers(body)

    assert {:ok, :accepted} = EnterpriseIdentity.accept_webhook(headers, body)
    assert {:ok, :duplicate} = EnterpriseIdentity.accept_webhook(headers, body)

    assert event_count("event_accepted") == 1
    assert archive_count("event_accepted") == 1
    assert operation_count("event_accepted") == 1

    assert [job] =
             all_enqueued(
               worker: DirectorySyncWorker,
               args: %{"provider_event_id" => "event_accepted"}
             )

    event =
      DirectorySyncEvent
      |> Ash.Query.filter(provider_event_id == "event_accepted")
      |> Ash.read_one!(authorize?: false)

    archive = Ash.get!(RawArchive, event.raw_archive_id, authorize?: false)

    assert archive.body == body
    assert archive.provider_event == "dsync.user.created"
    assert job.args["sync_event_id"] == event.id
    refute inspect(archive) =~ @secret
  end

  test "same event identity with changed content conflicts without a second job" do
    context = enterprise_context("conflict")
    body = user_body("event_conflict", context.directory.provider_directory_id)

    assert {:ok, :accepted} = EnterpriseIdentity.accept_webhook(signed_headers(body), body)

    changed =
      body
      |> Jason.decode!()
      |> put_in(["data", "first_name"], "Changed")
      |> Jason.encode!()

    assert {:error, :event_conflict} =
             EnterpriseIdentity.accept_webhook(signed_headers(changed), changed)

    assert event_count("event_conflict") == 1
    assert archive_count("event_conflict") == 1

    assert length(
             all_enqueued(
               worker: DirectorySyncWorker,
               args: %{"provider_event_id" => "event_conflict"}
             )
           ) == 1
  end

  test "invalid signatures and unknown directories create no receipt effects" do
    context = enterprise_context("rejected")
    invalid_body = user_body("event_invalid", context.directory.provider_directory_id)

    assert {:error, :invalid_signature} =
             EnterpriseIdentity.accept_webhook(
               %{"workos-signature" => "t=0,v1=" <> String.duplicate("0", 64)},
               invalid_body
             )

    unknown_body = user_body("event_unknown", "directory_unknown")

    assert {:error, :unknown_directory} =
             EnterpriseIdentity.accept_webhook(signed_headers(unknown_body), unknown_body)

    assert event_count("event_invalid") == 0
    assert event_count("event_unknown") == 0
    assert archive_count("event_invalid") == 0
    assert archive_count("event_unknown") == 0
    assert operation_count("event_invalid") == 0
    assert operation_count("event_unknown") == 0
  end

  test "worker applies the archived event and completes its sync event atomically" do
    context = enterprise_context("worker")
    body = user_body("event_worker", context.directory.provider_directory_id)

    assert {:ok, :accepted} = EnterpriseIdentity.accept_webhook(signed_headers(body), body)

    [job] =
      all_enqueued(
        worker: DirectorySyncWorker,
        args: %{"provider_event_id" => "event_worker"}
      )

    assert :ok = perform_job(DirectorySyncWorker, job.args)

    sync_event =
      DirectorySyncEvent
      |> Ash.Query.filter(provider_event_id == "event_worker")
      |> Ash.read_one!(authorize?: false)

    user =
      DirectoryUser
      |> Ash.Query.filter(
        directory_id == ^context.directory.id and provider_user_id == "directory_user_01"
      )
      |> Ash.read_one!(authorize?: false)

    assert sync_event.status == "applied"
    assert sync_event.result == "applied"
    assert %DateTime{} = sync_event.processed_at
    assert user.status == "active"
    assert user.email == "person@example.test"

    assert :ok = perform_job(DirectorySyncWorker, job.args)
    assert event_count("event_worker") == 1
    assert DirectoryUser |> Ash.Query.filter(id == ^user.id) |> Ash.count!(authorize?: false) == 1
  end

  defp enterprise_context(label) do
    {:ok, bootstrap} =
      Foundation.bootstrap_local_owner(
        organization_slug: unique("#{label}-organization"),
        workspace_slug: unique("#{label}-workspace"),
        initiative_slug: unique("#{label}-initiative"),
        owner_email: "#{unique(label)}@example.test"
      )

    {:ok, webhook_principal} =
      Identity.ensure_system_principal(
        "#{unique("#{label}-webhook")}@office-graph.local",
        "webhook"
      )

    assert :ok =
             Authorization.ensure_system_role(
               webhook_principal,
               %{
                 organization_id: bootstrap.organization.id,
                 workspace_id: bootstrap.workspace.id
               },
               [:provider_webhook_receive]
             )

    {:ok, setup_request} =
      Operations.new_system_operation_request(%{
        organization_id: bootstrap.organization.id,
        workspace_id: bootstrap.workspace.id,
        principal_id: webhook_principal.id,
        action: :provider_webhook_receive,
        authority_basis: "workos:setup:#{label}",
        causation_key: "workos:setup:#{label}",
        idempotency_scope: "workos:setup",
        idempotency_key: label
      })

    {:ok, setup_operation} = Operations.start_system_operation(setup_request)

    connection =
      Ash.create!(
        EnterpriseConnection,
        %{
          organization_id: bootstrap.organization.id,
          workspace_id: bootstrap.workspace.id,
          webhook_principal_id: webhook_principal.id,
          operation_id: setup_operation.id,
          provider: "workos",
          provider_organization_id: unique("workos-organization"),
          directory_requirement: "required",
          status: "active"
        },
        action: :create,
        authorize?: false
      )

    directory =
      Ash.create!(
        Directory,
        %{
          connection_id: connection.id,
          operation_id: setup_operation.id,
          provider_directory_id: unique("workos-directory"),
          status: "active",
          provider_updated_at: ~U[2026-07-29 19:00:00Z]
        },
        action: :create,
        authorize?: false
      )

    %{connection: connection, directory: directory}
  end

  defp user_body(event_id, directory_id) do
    Jason.encode!(%{
      "id" => event_id,
      "event" => "dsync.user.created",
      "created_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "data" => %{
        "id" => "directory_user_01",
        "idp_id" => "idp_user_01",
        "directory_id" => directory_id,
        "first_name" => "Ada",
        "last_name" => "Lovelace",
        "state" => "active",
        "updated_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "emails" => [%{"primary" => true, "value" => "Person@Example.TEST"}]
      }
    })
  end

  defp signed_headers(body) do
    timestamp = System.system_time(:second)

    signature =
      :crypto.mac(:hmac, :sha256, @secret, "#{timestamp}.#{body}")
      |> Base.encode16(case: :lower)

    %{"workos-signature" => "t=#{timestamp},v1=#{signature}"}
  end

  defp event_count(provider_event_id) do
    DirectorySyncEvent
    |> Ash.Query.filter(provider_event_id == ^provider_event_id)
    |> Ash.count!(authorize?: false)
  end

  defp archive_count(provider_event_id) do
    RawArchive
    |> Ash.Query.filter(external_delivery_id == ^provider_event_id)
    |> Ash.count!(authorize?: false)
  end

  defp operation_count(provider_event_id) do
    OperationCorrelation
    |> Ash.Query.filter(
      operation_kind == "system" and idempotency_scope == "workos:directory_delivery" and
        idempotency_key == ^provider_event_id
    )
    |> Ash.count!(authorize?: false)
  end

  defp restore_env(key, nil), do: Application.delete_env(:office_graph, key)
  defp restore_env(key, value), do: Application.put_env(:office_graph, key, value)

  defp unique(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
