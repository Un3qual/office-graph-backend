defmodule OfficeGraph.EnterpriseIdentity.Adapters.WorkOS.DirectoryEvent do
  @moduledoc false

  use Ash.TypedStruct

  typed_struct do
    field :provider_event_id, :string, allow_nil?: false
    field :event_type, :string, allow_nil?: false
    field :directory_id, :string, allow_nil?: false
    field :resource_kind, :atom, allow_nil?: false
    field :action, :atom, allow_nil?: false
    field :provider_occurred_at, :utc_datetime_usec, allow_nil?: false
    field :data, :map, allow_nil?: false
  end

  @maximum_body_bytes 1_000_000
  @maximum_identity_bytes 255
  @maximum_email_bytes 320

  @user_events %{
    "dsync.user.created" => :upsert,
    "dsync.user.updated" => :upsert,
    "dsync.user.deleted" => :delete
  }

  @group_events %{
    "dsync.group.created" => :upsert,
    "dsync.group.updated" => :upsert,
    "dsync.group.deleted" => :delete
  }

  @membership_events %{
    "dsync.group.user_added" => :add,
    "dsync.group.user_removed" => :remove
  }

  def normalize(raw_body)
      when is_binary(raw_body) and byte_size(raw_body) <= @maximum_body_bytes do
    with {:ok, envelope} <- Jason.decode(raw_body),
         {:ok, common} <- normalize_envelope(envelope),
         {:ok, event} <- normalize_data(common) do
      {:ok, event}
    else
      {:error, :unsupported_event} = error -> error
      _invalid -> {:error, :invalid_delivery}
    end
  end

  def normalize(_raw_body), do: {:error, :invalid_delivery}

  def content_hash(raw_body) when is_binary(raw_body) do
    :crypto.hash(:sha256, raw_body)
    |> Base.encode16(case: :lower)
  end

  defp normalize_envelope(%{
         "id" => provider_event_id,
         "event" => event_type,
         "created_at" => created_at,
         "data" => data
       })
       when is_map(data) do
    with {:ok, provider_event_id} <- bounded_string(provider_event_id, @maximum_identity_bytes),
         {:ok, event_type} <- bounded_string(event_type, @maximum_identity_bytes),
         {:ok, provider_occurred_at} <- timestamp(created_at),
         {:ok, event_kind, action} <- event_kind(event_type) do
      {:ok,
       %{
         provider_event_id: provider_event_id,
         event_type: event_type,
         provider_occurred_at: provider_occurred_at,
         event_kind: event_kind,
         action: action,
         data: data
       }}
    end
  end

  defp normalize_envelope(_envelope), do: {:error, :invalid_delivery}

  defp event_kind(event_type) do
    cond do
      action = @user_events[event_type] -> {:ok, :user, action}
      action = @group_events[event_type] -> {:ok, :group, action}
      action = @membership_events[event_type] -> {:ok, :membership, action}
      true -> {:error, :unsupported_event}
    end
  end

  defp normalize_data(%{event_kind: :user} = common) do
    data = common.data

    with {:ok, directory_id} <- bounded_string(data["directory_id"], @maximum_identity_bytes),
         {:ok, provider_user_id} <- bounded_string(data["id"], @maximum_identity_bytes),
         {:ok, email} <- primary_email(data["emails"]),
         {:ok, provider_updated_at} <-
           optional_timestamp(data["updated_at"], common.provider_occurred_at),
         {:ok, status} <- user_status(common.action, data["state"]) do
      {:ok,
       new_event(common, directory_id, %{
         provider_user_id: provider_user_id,
         idp_id: optional_bounded_string(data["idp_id"], @maximum_identity_bytes),
         email: email,
         first_name: optional_bounded_string(data["first_name"], @maximum_identity_bytes),
         last_name: optional_bounded_string(data["last_name"], @maximum_identity_bytes),
         status: status,
         provider_updated_at: provider_updated_at
       })}
    end
  end

  defp normalize_data(%{event_kind: :group} = common) do
    data = common.data

    with {:ok, directory_id} <- bounded_string(data["directory_id"], @maximum_identity_bytes),
         {:ok, provider_group_id} <- bounded_string(data["id"], @maximum_identity_bytes),
         {:ok, name} <- bounded_string(data["name"], @maximum_identity_bytes),
         {:ok, provider_updated_at} <-
           optional_timestamp(data["updated_at"], common.provider_occurred_at) do
      {:ok,
       new_event(common, directory_id, %{
         provider_group_id: provider_group_id,
         name: name,
         status: if(common.action == :delete, do: "deleted", else: "active"),
         provider_updated_at: provider_updated_at
       })}
    end
  end

  defp normalize_data(%{event_kind: :membership} = common) do
    data = common.data

    with {:ok, directory_id} <- bounded_string(data["directory_id"], @maximum_identity_bytes),
         {:ok, provider_group_id} <-
           nested_identity(data["group"], @maximum_identity_bytes),
         {:ok, provider_user_id} <-
           nested_identity(data["user"], @maximum_identity_bytes) do
      {:ok,
       new_event(common, directory_id, %{
         provider_group_id: provider_group_id,
         provider_user_id: provider_user_id,
         status: if(common.action == :add, do: "active", else: "removed"),
         provider_updated_at: common.provider_occurred_at
       })}
    end
  end

  defp new_event(common, directory_id, data) do
    new!(
      provider_event_id: common.provider_event_id,
      event_type: common.event_type,
      directory_id: directory_id,
      resource_kind: common.event_kind,
      action: common.action,
      provider_occurred_at: common.provider_occurred_at,
      data: data
    )
  end

  defp primary_email(emails) when is_list(emails) do
    primary =
      Enum.find(emails, fn
        %{"primary" => true} -> true
        _other -> false
      end) || List.first(emails)

    case primary do
      %{"value" => value} ->
        with {:ok, email} <- bounded_string(value, @maximum_email_bytes) do
          {:ok, String.downcase(email)}
        end

      _invalid ->
        {:error, :invalid_delivery}
    end
  end

  defp primary_email(_emails), do: {:error, :invalid_delivery}

  defp user_status(:delete, _provider_state), do: {:ok, "deleted"}
  defp user_status(_action, "active"), do: {:ok, "active"}

  defp user_status(_action, state) when state in ["inactive", "suspended"],
    do: {:ok, "suspended"}

  defp user_status(_action, _state), do: {:error, :invalid_delivery}

  defp nested_identity(%{"id" => value}, maximum_bytes),
    do: bounded_string(value, maximum_bytes)

  defp nested_identity(_value, _maximum_bytes), do: {:error, :invalid_delivery}

  defp optional_bounded_string(nil, _maximum_bytes), do: nil

  defp optional_bounded_string(value, maximum_bytes) do
    case bounded_string(value, maximum_bytes) do
      {:ok, normalized} -> normalized
      {:error, _reason} -> nil
    end
  end

  defp bounded_string(value, maximum_bytes)
       when is_binary(value) and byte_size(value) <= maximum_bytes do
    case String.trim(value) do
      "" -> {:error, :invalid_delivery}
      trimmed -> {:ok, trimmed}
    end
  end

  defp bounded_string(_value, _maximum_bytes), do: {:error, :invalid_delivery}

  defp optional_timestamp(nil, fallback), do: {:ok, fallback}
  defp optional_timestamp(value, _fallback), do: timestamp(value)

  defp timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, 0} -> {:ok, date_time}
      _invalid -> {:error, :invalid_delivery}
    end
  end

  defp timestamp(_value), do: {:error, :invalid_delivery}
end
