import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import { OperatorLayout } from "./operator/components/OperatorLayout";
import { PacketsLayout } from "./packets/components/PacketsLayout";
import { PRODUCT_DESTINATIONS } from "./productNavigation";

describe("product navigation configuration", () => {
  it("exports the product destination values directly", () => {
    expect(PRODUCT_DESTINATIONS).toEqual([
      { label: "Operator", to: "/operator" },
      { label: "Packets", to: "/packets" },
      { label: "All Runs" },
      { label: "Entities" },
      { label: "Reports" }
    ]);
  });

  it("renders operator navigation behavior from the shared destinations", () => {
    render(
      <MemoryRouter initialEntries={["/operator"]}>
        <OperatorLayout detail={<p>Detail</p>} inbox={<p>Inbox</p>} inspector={<p>Inspector</p>} />
      </MemoryRouter>
    );

    expectProductNavigation("Operator");
  });

  it("renders packet navigation behavior from the shared destinations", () => {
    render(
      <MemoryRouter initialEntries={["/packets"]}>
        <PacketsLayout detail={<p>Detail</p>} list={<p>List</p>} />
      </MemoryRouter>
    );

    expectProductNavigation("Packets");
  });
});

function expectProductNavigation(activeLabel: "Operator" | "Packets") {
  expect(screen.getByRole("link", { name: "Operator" })).toHaveAttribute(
    "href",
    "/operator"
  );
  expect(screen.getByRole("link", { name: "Packets" })).toHaveAttribute(
    "href",
    "/packets"
  );
  expect(screen.getByRole("link", { name: activeLabel })).toHaveAttribute(
    "aria-current",
    "page"
  );

  for (const label of ["All Runs", "Entities", "Reports"]) {
    expect(screen.getByRole("button", { name: label })).toBeDisabled();
    expect(screen.queryByRole("link", { name: label })).not.toBeInTheDocument();
  }
}
