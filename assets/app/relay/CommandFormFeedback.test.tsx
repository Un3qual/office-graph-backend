import { createRef } from "react";
import { render, waitFor } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { CommandFormFeedback, commandFieldErrorsForState } from "./CommandFormFeedback";

describe("command form feedback effects", () => {
  it("reuses one empty field-error collection across unrelated states", () => {
    const idle = commandFieldErrorsForState({ status: "idle" });
    const pending = commandFieldErrorsForState({ status: "pending" });
    const success = commandFieldErrorsForState({
      status: "success",
      operationId: "operation-1",
      affectedIds: [],
      result: null,
    });

    expect(idle).toBe(pending);
    expect(pending).toBe(success);
  });

  it("focuses the first editable invalid control and skips unusable matches", async () => {
    const formRef = createRef<HTMLFormElement>();
    const form = (state: Parameters<typeof CommandFormFeedback>[0]["state"]) => (
      <form ref={formRef}>
        <input aria-invalid="true" name="contextSummary" type="hidden" />
        <input aria-invalid="true" disabled name="contextSummary" />
        <input aria-invalid="true" name="contextSummary" readOnly />
        <input aria-invalid="true" name="contextSummary" tabIndex={-1} />
        <label>
          Context summary
          <textarea aria-invalid="true" name="contextSummary" />
        </label>
        <CommandFormFeedback formRef={formRef} state={state} />
      </form>
    );
    const { getByLabelText, rerender } = render(form({ status: "idle" }));

    rerender(
      form({
        status: "field-error",
        fields: [{ field: "context_summary", message: "Add current product context." }],
      }),
    );

    await waitFor(() => expect(getByLabelText("Context summary")).toHaveFocus());
  });
});
