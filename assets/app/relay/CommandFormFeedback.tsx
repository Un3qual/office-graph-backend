import { useLayoutEffect, type RefObject } from "react";
import { FormFeedback } from "../../src/ui/FormFeedback";
import type {
  CommandFieldError as CommandFieldErrorValue,
  CommandMutationState,
} from "./commandMutation";
import {
  commandFeedback,
  commandFieldErrorId,
  commandFieldErrors,
  commandFieldName,
} from "./commandFormSupport";

type FeedbackProps<TResult> = {
  readonly formRef: RefObject<HTMLFormElement | null>;
  readonly pendingMessage?: string | null;
  readonly state: CommandMutationState<TResult>;
};

const EMPTY_FIELD_ERRORS: readonly CommandFieldErrorValue[] = Object.freeze([]);

export function commandFieldErrorsForState<TResult>(state: CommandMutationState<TResult>) {
  return state.status === "field-error" ? state.fields : EMPTY_FIELD_ERRORS;
}

export function CommandFormFeedback<TResult>({
  formRef,
  pendingMessage = null,
  state,
}: FeedbackProps<TResult>) {
  const fieldErrors = commandFieldErrorsForState(state);

  useLayoutEffect(() => {
    if (fieldErrors.length === 0) return;

    const controls = Array.from(formRef.current?.elements ?? []);
    const firstInvalidControl = fieldErrors
      .map(({ field }) => commandFieldName(field))
      .map((name) =>
        controls.find(
          (control) => control.getAttribute("name") === name && isEditableInvalidControl(control),
        ),
      )
      .find((control): control is EditableFormControl => isEditableInvalidControl(control));

    firstInvalidControl?.focus();
  }, [fieldErrors, formRef]);

  if (fieldErrors.length === 0) {
    return <FormFeedback feedback={commandFeedback(state)} pendingMessage={pendingMessage} />;
  }

  return (
    <div className="ui-form-feedback" data-kind="field" role="alert">
      <p>Correct the following fields:</p>
      <ul>
        {fieldErrors.map(({ field, message }) => (
          <li key={`${field}:${message}`}>{message}</li>
        ))}
      </ul>
    </div>
  );
}

type EditableFormControl = HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement;

function isEditableInvalidControl(control: Element | undefined): control is EditableFormControl {
  if (
    !control ||
    control.getAttribute("aria-invalid") !== "true" ||
    control.getAttribute("aria-disabled") === "true" ||
    control.closest("[hidden], [inert], [aria-hidden='true']") ||
    control.matches(":disabled") ||
    (control instanceof HTMLElement && control.hasAttribute("tabindex") && control.tabIndex < 0)
  ) {
    return false;
  }

  if (control instanceof HTMLInputElement) {
    return (
      !control.disabled &&
      !control.readOnly &&
      !["hidden", "button", "submit", "reset", "image"].includes(control.type)
    );
  }

  if (control instanceof HTMLTextAreaElement) {
    return !control.disabled && !control.readOnly;
  }

  return control instanceof HTMLSelectElement && !control.disabled;
}

type FieldErrorProps<TResult> = {
  readonly controlName: string;
  readonly scope: string;
  readonly state: CommandMutationState<TResult>;
};

export function CommandFieldError<TResult>({
  controlName,
  scope,
  state,
}: FieldErrorProps<TResult>) {
  const errors = commandFieldErrors(state, controlName);
  if (errors.length === 0) return null;

  return (
    <span className="ui-field-error" id={commandFieldErrorId(scope, controlName)}>
      {errors.map(({ message }) => message).join(" ")}
    </span>
  );
}
