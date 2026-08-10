defmodule OfficeGraph.PersistenceFailureResponsesTest do
  use ExUnit.Case, async: true

  alias OfficeGraphTest.PersistenceFailureResponses

  test "shares configured responses only with the configuring process tree" do
    PersistenceFailureResponses.configure!(:example, write: {:error, :unavailable})

    assert PersistenceFailureResponses.fetch(:example, :write) == {:error, :unavailable}

    assert Task.async(fn -> PersistenceFailureResponses.fetch(:example, :write) end)
           |> Task.await() ==
             {:error, :unavailable}

    parent = self()

    spawn(fn ->
      send(parent, {:unrelated_response, PersistenceFailureResponses.fetch(:example, :write)})
    end)

    assert_receive {:unrelated_response, :ok}
  end
end
