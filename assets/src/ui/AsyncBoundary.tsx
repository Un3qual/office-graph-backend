import { Component, Suspense, type ReactElement, type ReactNode } from "react";

type AsyncBoundaryProps = {
  children: ReactNode;
  errorFallback: ReactNode;
  loadingFallback: ReactNode;
  resetKey: string | number | null;
};

type ErrorBoundaryProps = Pick<AsyncBoundaryProps, "children" | "errorFallback" | "resetKey">;

type ErrorBoundaryState = {
  hasError: boolean;
};

export function AsyncBoundary({
  children,
  errorFallback,
  loadingFallback,
  resetKey,
}: AsyncBoundaryProps): ReactElement {
  return (
    <ErrorBoundary errorFallback={errorFallback} resetKey={resetKey}>
      <Suspense fallback={loadingFallback}>{children}</Suspense>
    </ErrorBoundary>
  );
}

class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false };

  static getDerivedStateFromError(): ErrorBoundaryState {
    return { hasError: true };
  }

  componentDidUpdate(previousProps: ErrorBoundaryProps) {
    if (this.state.hasError && previousProps.resetKey !== this.props.resetKey) {
      this.setState({ hasError: false });
    }
  }

  render() {
    return this.state.hasError ? this.props.errorFallback : this.props.children;
  }
}
