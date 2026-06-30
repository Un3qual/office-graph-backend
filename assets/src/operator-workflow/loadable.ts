export type Loadable<T> =
  | { state: "idle" | "loading" }
  | { state: "loaded"; data: T }
  | { state: "error"; message: string };

export function errorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }

  return "The operator workflow request failed.";
}
