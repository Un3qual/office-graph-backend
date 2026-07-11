export type FormFeedbackMessage = {
  readonly field?: string;
  readonly kind: "conflict" | "error" | "field";
  readonly message: string;
};

type Props = {
  readonly feedback?: FormFeedbackMessage | null;
  readonly pendingMessage?: string | null;
};

export function FormFeedback({ feedback = null, pendingMessage = null }: Props) {
  if (pendingMessage) {
    return (
      <p className="ui-form-feedback" data-kind="pending" role="status">
        {pendingMessage}
      </p>
    );
  }

  if (!feedback) {
    return null;
  }

  return (
    <p
      className="ui-form-feedback"
      data-field={feedback.field}
      data-kind={feedback.kind}
      role="alert"
    >
      {feedback.message}
    </p>
  );
}
