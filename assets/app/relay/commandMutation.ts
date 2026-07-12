import { useCallback, useEffect, useRef, useState } from "react";
import { commitMutation, useRelayEnvironment } from "react-relay";
import type {
  Disposable,
  GraphQLTaggedNode,
  MutationParameters
} from "relay-runtime";
import { GraphQLResponseError } from "./fetchGraphQL";

export type CommandAffectedId = {
  readonly id: string;
  readonly type: string;
};

export type CommandFieldError = {
  readonly field: string;
  readonly message: string;
};

export type CommandMutationState<TResult> =
  | { readonly status: "idle" }
  | { readonly status: "pending" }
  | { readonly status: "field-error"; readonly fields: readonly CommandFieldError[] }
  | { readonly status: "conflict"; readonly code: string; readonly message: string }
  | { readonly status: "error"; readonly code: string; readonly message: string }
  | ({ readonly status: "success" } & CommandMutationSuccess<TResult>);

export type CommandMutationSuccess<TResult> = {
  readonly operationId: string;
  readonly affectedIds: readonly CommandAffectedId[];
  readonly result: TResult;
};

export type CommandMutationConfig<
  TMutation extends MutationParameters,
  TInput,
  TResult
> = {
  readonly mutation: GraphQLTaggedNode;
  readonly toVariables: (input: TInput) => TMutation["variables"];
  readonly mapSuccess: (
    response: TMutation["response"]
  ) => CommandMutationSuccess<TResult>;
};

export type CommandMutationController<TInput, TResult> = {
  readonly reset: () => void;
  readonly state: CommandMutationState<TResult>;
  readonly submit: (input: TInput) => boolean;
};

type SafePayloadError = {
  readonly extensions?: Record<string, unknown> | null;
  readonly message: string;
};

const conflictCodes = new Set([
  "active_work_run",
  "evidence_candidate_already_accepted",
  "idempotency_conflict",
  "invalid_proposed_change_set",
  "invalid_proposed_change_status",
  "invalid_verification_check_status",
  "manual_intake_replay_conflict",
  "packet_version_not_ready",
  "stale_packet_version",
  "stale_run_state",
  "verification_result_slot_conflict"
]);

const unknownFailure = {
  status: "error",
  code: "unknown",
  message: "Unable to complete this action. Try again."
} as const;

export function useCommandMutation<
  TMutation extends MutationParameters,
  TInput,
  TResult
>(
  config: CommandMutationConfig<TMutation, TInput, TResult>,
  onAuthoritativeChange?: (success?: CommandMutationSuccess<TResult>) => void
): CommandMutationController<TInput, TResult> {
  const environment = useRelayEnvironment();
  const activeRequest = useRef<Disposable | null>(null);
  const pending = useRef(false);
  const authoritativeChange = useRef(onAuthoritativeChange);
  authoritativeChange.current = onAuthoritativeChange;
  const [state, setState] = useState<CommandMutationState<TResult>>({ status: "idle" });

  const reset = useCallback(() => {
    activeRequest.current?.dispose();
    activeRequest.current = null;
    pending.current = false;
    setState({ status: "idle" });
  }, []);

  const submit = useCallback(
    (input: TInput) => {
      if (pending.current) {
        return false;
      }

      pending.current = true;
      setState({ status: "pending" });

      activeRequest.current = commitMutation<TMutation>(environment, {
        mutation: config.mutation,
        variables: config.toVariables(input),
        onCompleted(response, errors) {
          pending.current = false;
          activeRequest.current = null;

          if (errors && errors.length > 0) {
            const nextState = mapPayloadErrors(errors);
            setState(nextState);
            if (nextState.status === "conflict") authoritativeChange.current?.();
            return;
          }

          const success = config.mapSuccess(response);
          setState({ status: "success", ...success });
          authoritativeChange.current?.(success);
        },
        onError(error) {
          pending.current = false;
          activeRequest.current = null;
          const nextState = mapCommandFailure(error);
          setState(nextState);
          if (nextState.status === "conflict") authoritativeChange.current?.();
        }
      });

      return true;
    },
    [config, environment]
  );

  useEffect(() => {
    return () => activeRequest.current?.dispose();
  }, []);

  return { reset, state, submit };
}

export function commandMutationSuccess<TResult>(
  payload: {
    readonly affectedIds: readonly CommandAffectedId[];
    readonly operationId: string;
  },
  result: TResult
): CommandMutationSuccess<TResult> {
  return {
    operationId: payload.operationId,
    affectedIds: payload.affectedIds,
    result
  };
}

export function mapCommandFailure(
  failure: Error
): Exclude<CommandMutationState<never>, { status: "idle" | "pending" | "success" }> {
  if (!(failure instanceof GraphQLResponseError)) {
    return unknownFailure;
  }

  const errors =
    !Array.isArray(failure.source) && "errors" in failure.source
      ? failure.source.errors
      : null;
  return errors && errors.length > 0 ? mapPayloadErrors(errors) : unknownFailure;
}

function mapPayloadErrors(
  errors: readonly SafePayloadError[]
): Exclude<CommandMutationState<never>, { status: "idle" | "pending" | "success" }> {
  const fields = errors.flatMap(payloadError => {
    const extensions = payloadError.extensions;
    const field = extensions?.field;

    return extensions?.code === "validation_failed" && typeof field === "string"
      ? [{ field, message: payloadError.message }]
      : [];
  });

  if (fields.length > 0) {
    return { status: "field-error", fields };
  }

  const firstError = errors[0];

  if (!firstError) {
    return unknownFailure;
  }

  const code = firstError.extensions?.code;

  if (typeof code !== "string") {
    return unknownFailure;
  }

  if (conflictCodes.has(code)) {
    return { status: "conflict", code, message: firstError.message };
  }

  return { status: "error", code, message: firstError.message };
}
