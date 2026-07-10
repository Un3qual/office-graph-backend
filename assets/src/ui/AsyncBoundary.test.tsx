import { act, render, screen } from "@testing-library/react";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { AsyncBoundary } from "./AsyncBoundary";

describe("AsyncBoundary", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("renders caller-supplied loading content while its child suspends", async () => {
    const deferred = deferredRender();

    render(
      <AsyncBoundary
        errorFallback={<p role="alert">Safe unavailable state</p>}
        loadingFallback={<p role="status">Loading content</p>}
        resetKey="initial"
      >
        <DeferredChild deferred={deferred}>Loaded content</DeferredChild>
      </AsyncBoundary>
    );

    expect(screen.getByRole("status")).toHaveTextContent("Loading content");

    await act(async () => deferred.resolve());

    expect(await screen.findByText("Loaded content")).toBeInTheDocument();
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("renders only caller-supplied safe content when its child throws", () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);

    render(
      <AsyncBoundary
        errorFallback={<p role="alert">Safe unavailable state</p>}
        loadingFallback={<p role="status">Loading content</p>}
        resetKey="initial"
      >
        <ThrowingChild />
      </AsyncBoundary>
    );

    expect(screen.getByRole("alert")).toHaveTextContent("Safe unavailable state");
    expect(document.body).not.toHaveTextContent("authorization secret_alpha");
  });

  it("attempts to render new children when the reset key changes", async () => {
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    const { rerender } = render(
      <AsyncBoundary
        errorFallback={<p role="alert">Safe unavailable state</p>}
        loadingFallback={<p role="status">Loading content</p>}
        resetKey="packet:cursor_1"
      >
        <ThrowingChild />
      </AsyncBoundary>
    );

    expect(screen.getByRole("alert")).toBeInTheDocument();

    rerender(
      <AsyncBoundary
        errorFallback={<p role="alert">Safe unavailable state</p>}
        loadingFallback={<p role="status">Loading content</p>}
        resetKey="packet:cursor_2"
      >
        <p>Recovered content</p>
      </AsyncBoundary>
    );

    expect(await screen.findByText("Recovered content")).toBeInTheDocument();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
  });
});

function ThrowingChild(): never {
  throw new Error("authorization secret_alpha");
}

function DeferredChild({
  children,
  deferred
}: {
  children: ReactNode;
  deferred: ReturnType<typeof deferredRender>;
}) {
  if (!deferred.resolved()) {
    throw deferred.promise;
  }

  return children;
}

function deferredRender() {
  let isResolved = false;
  let resolvePromise!: () => void;
  const promise = new Promise<void>((resolve) => {
    resolvePromise = resolve;
  });

  return {
    promise,
    resolved: () => isResolved,
    resolve: () => {
      isResolved = true;
      resolvePromise();
    }
  };
}
