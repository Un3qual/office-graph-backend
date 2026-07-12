defmodule OfficeGraph.Runs.ObservationStateReducerTest do
  use ExUnit.Case, async: true

  alias OfficeGraph.Runs.ObservationStateReducer

  test "failed observations reduce every prior lifecycle to failed" do
    assert :failed =
             ObservationStateReducer.next_state(
               %{
                 aggregate_state: "verified",
                 execution_state: "completed",
                 verification_state: "verified"
               },
               "failed",
               false
             )
  end

  test "successful observations preserve verified and failed truth" do
    assert :preserve =
             ObservationStateReducer.next_state(
               %{
                 aggregate_state: "verified",
                 execution_state: "completed",
                 verification_state: "verified"
               },
               "succeeded",
               false
             )

    assert :preserve =
             ObservationStateReducer.next_state(
               %{
                 aggregate_state: "failed",
                 execution_state: "failed",
                 verification_state: "failed"
               },
               "succeeded",
               true
             )

    assert :preserve =
             ObservationStateReducer.next_state(
               %{
                 state: "verified",
                 aggregate_state: "running",
                 execution_state: "running",
                 verification_state: "pending"
               },
               "succeeded",
               false
             )

    assert :preserve =
             ObservationStateReducer.next_state(
               %{
                 state: "failed",
                 aggregate_state: "running",
                 execution_state: "running",
                 verification_state: "pending"
               },
               "succeeded",
               false
             )
  end

  test "successful observations reduce prior failed evidence to failed truth" do
    assert :failed =
             ObservationStateReducer.next_state(
               %{
                 aggregate_state: "running",
                 execution_state: "running",
                 verification_state: "pending"
               },
               "succeeded",
               true
             )
  end

  test "a first successful observation advances an active run to awaiting verification" do
    assert :awaiting_verification =
             ObservationStateReducer.next_state(
               %{
                 aggregate_state: "running",
                 execution_state: "running",
                 verification_state: "pending"
               },
               "succeeded",
               false
             )
  end
end
