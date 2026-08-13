defmodule OfficeGraph.NodeConversations.ActionSupportTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.NodeConversations.ActionSupport

  test "programmer failures keep their original classification" do
    assert_raise RuntimeError, "conversation action bug", fn ->
      ActionSupport.run(fn -> raise "conversation action bug" end)
    end
  end

  test "raised Ash authorization failures are not reported as storage outages" do
    error = Ash.Error.Forbidden.exception(errors: [])

    assert_raise Ash.Error.Forbidden, fn ->
      ActionSupport.run(fn -> raise error end)
    end
  end

  test "database checkout exits are reported as storage outages" do
    assert {:error, :integration_storage_unavailable} =
             ActionSupport.run(fn ->
               exit(
                 {:noproc,
                  {DBConnection.Holder, :checkout, [:missing_node_conversations_pool, []]}}
               )
             end)
  end

  test "unrelated exits keep their original classification" do
    assert catch_exit(ActionSupport.run(fn -> exit(:conversation_action_bug) end)) ==
             :conversation_action_bug
  end
end
