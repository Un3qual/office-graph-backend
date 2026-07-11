import { describe, expect, it } from "vitest";
import { GraphQLResponseError } from "./fetchGraphQL";
import { mapCommandFailure } from "./commandMutation";

describe("command mutation failure mapping", () => {
  it("maps every field-specific validation error without losing safe server copy", () => {
    const failure = graphQLError([
      error("A required field is missing.", "validation_failed", { field: "body" }),
      error("A field has an invalid value.", "validation_failed", {
        field: "source_identity"
      })
    ]);

    expect(mapCommandFailure(failure)).toEqual({
      status: "field-error",
      fields: [
        { field: "body", message: "A required field is missing." },
        { field: "source_identity", message: "A field has an invalid value." }
      ]
    });
  });

  it.each([
    "idempotency_conflict",
    "manual_intake_replay_conflict",
    "stale_packet_version",
    "stale_run_state",
    "invalid_proposed_change_status",
    "invalid_proposed_change_set",
    "invalid_verification_check_status",
    "packet_version_not_ready"
  ])("maps %s as a conflict that requires an explicit retry", code => {
    expect(
      mapCommandFailure(graphQLError([error("Refresh before retrying.", code)]))
    ).toEqual({
      status: "conflict",
      code,
      message: "Refresh before retrying."
    });
  });

  it("preserves safe forbidden copy without exposing transport details", () => {
    expect(
      mapCommandFailure(
        graphQLError([error("The action is not authorized.", "forbidden")])
      )
    ).toEqual({
      status: "error",
      code: "forbidden",
      message: "The action is not authorized."
    });
  });

  it("replaces unknown runtime failures with generic copy", () => {
    expect(mapCommandFailure(new Error("internal socket details"))).toEqual({
      status: "error",
      code: "unknown",
      message: "Unable to complete this action. Try again."
    });
  });
});

function error(message: string, code: string, extra: Record<string, unknown> = {}) {
  return { message, extensions: { code, ...extra } };
}

function graphQLError(errors: ReturnType<typeof error>[]) {
  return new GraphQLResponseError(
    errors[0]?.message ?? "Request failed.",
    { errors },
    200,
    "TestCommandMutation"
  );
}
