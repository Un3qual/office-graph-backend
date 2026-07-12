import { useLayoutEffect, type RefObject } from "react";
import { FormFeedback } from "../../src/ui/FormFeedback";
import type { CommandMutationState } from "./commandMutation";
import {
  commandFeedback,
  commandFieldErrorId,
  commandFieldErrors,
  commandFieldName
} from "./commandFormSupport";

type FeedbackProps<TResult> = {
  readonly formRef: RefObject<HTMLFormElement | null>;
  readonly pendingMessage?: string | null;
  readonly scope: string;
  readonly state: CommandMutationState<TResult>;
};

export function CommandFormFeedback<TResult>({
  formRef,
  pendingMessage = null,
  scope,
  state
}: FeedbackProps<TResult>) {
  const fieldErrors = state.status === "field-error" ? state.fields : [];

  useLayoutEffect(() => {
    if (fieldErrors.length === 0) return;

    const controls = Array.from(formRef.current?.elements ?? []);
    const firstInvalidControl = fieldErrors
      .map(({ field }) => commandFieldName(field))
      .map((name) => controls.find((control) => control.getAttribute("name") === name))
      .find((control): control is HTMLElement => control instanceof HTMLElement);

    firstInvalidControl?.focus();
  }, [fieldErrors, formRef]);

  if (fieldErrors.length === 0) {
    return (
      <FormFeedback
        feedback={commandFeedback(state)}
        pendingMessage={pendingMessage}
      />
    );
  }

  return (
    <div className="ui-form-feedback" data-kind="field" role="alert">
      <p>Correct the following fields:</p>
      <ul>
        {fieldErrors.map(({ field, message }, index) => (
          <li key={`${field}:${index}`}>{message}</li>
        ))}
      </ul>
    </div>
  );
}

type FieldErrorProps<TResult> = {
  readonly controlName: string;
  readonly scope: string;
  readonly state: CommandMutationState<TResult>;
};

export function CommandFieldError<TResult>({
  controlName,
  scope,
  state
}: FieldErrorProps<TResult>) {
  const errors = commandFieldErrors(state, controlName);
  if (errors.length === 0) return null;

  return (
    <span
      className="ui-field-error"
      id={commandFieldErrorId(scope, controlName)}
    >
      {errors.map(({ message }) => message).join(" ")}
    </span>
  );
}
