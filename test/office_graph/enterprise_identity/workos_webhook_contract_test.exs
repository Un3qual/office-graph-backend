defmodule OfficeGraph.EnterpriseIdentity.WorkOSWebhookContractTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.{
    DirectoryEvent,
    WebhookSignature
  }

  @secret "whsec_test_secret"
  @timestamp 1_785_300_000

  test "verifies the timestamped HMAC over the exact raw body" do
    raw_body = ~s({"id":"event_01","event":"dsync.user.created"})
    header = signature_header(raw_body, @timestamp)

    assert :ok =
             WebhookSignature.verify(raw_body, header, @secret,
               now_unix: @timestamp + 30,
               tolerance_seconds: 180
             )

    assert {:error, :invalid_signature} =
             WebhookSignature.verify(raw_body <> " ", header, @secret,
               now_unix: @timestamp + 30,
               tolerance_seconds: 180
             )
  end

  test "rejects malformed, stale, and future signatures" do
    raw_body = ~s({"id":"event_01"})
    header = signature_header(raw_body, @timestamp)

    for invalid_header <- [nil, "", "v1=abc", "t=abc,v1=abc", "t=#{@timestamp},v1=zz"] do
      assert {:error, :invalid_signature} =
               WebhookSignature.verify(raw_body, invalid_header, @secret,
                 now_unix: @timestamp,
                 tolerance_seconds: 180
               )
    end

    assert {:error, :invalid_signature} =
             WebhookSignature.verify(raw_body, header, @secret,
               now_unix: @timestamp + 181,
               tolerance_seconds: 180
             )

    assert {:error, :invalid_signature} =
             WebhookSignature.verify(raw_body, header, @secret,
               now_unix: @timestamp - 181,
               tolerance_seconds: 180
             )
  end

  test "normalizes a WorkOS directory user without raw attributes or external roles" do
    raw_body =
      Jason.encode!(%{
        "id" => "event_user_01",
        "event" => "dsync.user.updated",
        "created_at" => "2026-07-29T20:00:00.000Z",
        "data" => %{
          "id" => "directory_user_01",
          "idp_id" => "idp_user_01",
          "directory_id" => "directory_01",
          "first_name" => " Ada ",
          "last_name" => " Lovelace ",
          "state" => "active",
          "updated_at" => "2026-07-29T19:59:00.000Z",
          "emails" => [
            %{"primary" => false, "value" => "other@example.com"},
            %{"primary" => true, "value" => " Person@Example.COM "}
          ],
          "raw_attributes" => %{
            "groups" => ["administrator"],
            "office_graph_role_id" => "do-not-trust"
          }
        }
      })

    assert {:ok, event} = DirectoryEvent.normalize(raw_body)

    assert event.provider_event_id == "event_user_01"
    assert event.event_type == "dsync.user.updated"
    assert event.directory_id == "directory_01"
    assert event.resource_kind == :user
    assert event.action == :upsert
    assert DateTime.compare(event.provider_occurred_at, ~U[2026-07-29 20:00:00.000Z]) == :eq

    assert %{
             provider_user_id: "directory_user_01",
             idp_id: "idp_user_01",
             email: "person@example.com",
             first_name: "Ada",
             last_name: "Lovelace",
             status: "active",
             provider_updated_at: provider_updated_at
           } = event.data

    assert DateTime.compare(provider_updated_at, ~U[2026-07-29 19:59:00.000Z]) == :eq

    refute inspect(event) =~ "administrator"
    refute inspect(event) =~ "do-not-trust"
  end

  test "normalizes group and membership lifecycle events" do
    assert {:ok, group} =
             DirectoryEvent.normalize(
               event_body("event_group", "dsync.group.deleted", %{
                 "id" => "group_01",
                 "directory_id" => "directory_01",
                 "name" => "Engineering",
                 "updated_at" => "2026-07-29T20:00:00Z"
               })
             )

    assert group.resource_kind == :group
    assert group.action == :delete
    assert group.data.status == "deleted"

    assert {:ok, membership} =
             DirectoryEvent.normalize(
               event_body("event_member", "dsync.group.user_removed", %{
                 "directory_id" => "directory_01",
                 "group" => %{"id" => "group_01"},
                 "user" => %{"id" => "directory_user_01"}
               })
             )

    assert membership.resource_kind == :membership
    assert membership.action == :remove

    assert membership.data == %{
             provider_group_id: "group_01",
             provider_user_id: "directory_user_01",
             status: "removed",
             provider_updated_at: ~U[2026-07-29 20:00:00Z]
           }
  end

  test "rejects unknown event types and malformed bounded fields" do
    assert {:error, :unsupported_event} =
             DirectoryEvent.normalize(event_body("event_unknown", "dsync.unknown", %{}))

    assert {:error, :invalid_delivery} =
             DirectoryEvent.normalize(
               event_body("event_user", "dsync.user.created", %{
                 "id" => "directory_user_01",
                 "directory_id" => "directory_01",
                 "emails" => [],
                 "state" => "active"
               })
             )
  end

  test "rejects present optional user fields that are malformed or over limit" do
    for invalid_first_name <- [42, "", String.duplicate("x", 256)] do
      assert {:error, :invalid_delivery} =
               DirectoryEvent.normalize(
                 event_body("event_optional_user", "dsync.user.updated", %{
                   "id" => "directory_user_01",
                   "directory_id" => "directory_01",
                   "first_name" => invalid_first_name,
                   "emails" => [%{"primary" => true, "value" => "person@example.com"}],
                   "state" => "active"
                 })
               )
    end
  end

  defp event_body(id, event, data) do
    Jason.encode!(%{
      "id" => id,
      "event" => event,
      "created_at" => "2026-07-29T20:00:00Z",
      "data" => data
    })
  end

  defp signature_header(raw_body, timestamp) do
    signature =
      :crypto.mac(:hmac, :sha256, @secret, "#{timestamp}.#{raw_body}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{signature}"
  end
end
