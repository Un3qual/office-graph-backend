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
end
