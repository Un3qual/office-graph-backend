import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import routes from "../routes";
import { OperatorLayout } from "./operator/components/OperatorLayout";
import { PacketsLayout } from "./packets/components/PacketsLayout";
import { PRODUCT_DESTINATIONS } from "./productNavigation";
import { RunsLayout } from "./runs/components/RunsLayout";

describe("product navigation configuration", () => {
  it("exports the product destination values directly", () => {
    expect(PRODUCT_DESTINATIONS).toEqual([
      { label: "Operator", to: "/operator" },
      { label: "Packets", to: "/packets" },
      { label: "All Runs", to: "/runs" },
      { label: "Entities" },
      { label: "Reports" },
    ]);
  });

  it("registers the all-runs React Router route", () => {
    expect(routes).toContainEqual(
      expect.objectContaining({
        file: "./routes/runs/route.tsx",
        path: "runs",
      }),
    );
  });

  it("renders operator navigation behavior from the shared destinations", () => {
    render(
      <MemoryRouter initialEntries={["/operator"]}>
        <OperatorLayout detail={<p>Detail</p>} inbox={<p>Inbox</p>} inspector={<p>Inspector</p>} />
      </MemoryRouter>,
    );

    expectProductNavigation("Operator");
  });

  it("renders packet navigation behavior from the shared destinations", () => {
    render(
      <MemoryRouter initialEntries={["/packets"]}>
        <PacketsLayout detail={<p>Detail</p>} list={<p>List</p>} />
      </MemoryRouter>,
    );

    expectProductNavigation("Packets");
  });

  it("renders all-runs active navigation behavior from the shared destinations", () => {
    render(
      <MemoryRouter initialEntries={["/runs"]}>
        <RunsLayout detail={<p>Detail</p>} list={<p>List</p>} />
      </MemoryRouter>,
    );

    expectProductNavigation("All Runs");
  });
});

function expectProductNavigation(activeLabel: "All Runs" | "Operator" | "Packets") {
  expect(screen.getByRole("link", { name: "Operator" })).toHaveAttribute("href", "/operator");
  expect(screen.getByRole("link", { name: "Packets" })).toHaveAttribute("href", "/packets");
  expect(screen.getByRole("link", { name: "All Runs" })).toHaveAttribute("href", "/runs");
  expect(screen.getByRole("link", { name: activeLabel })).toHaveAttribute("aria-current", "page");

  for (const label of ["Entities", "Reports"]) {
    expect(screen.getByRole("button", { name: label })).toBeDisabled();
    expect(screen.queryByRole("link", { name: label })).not.toBeInTheDocument();
  }
}
