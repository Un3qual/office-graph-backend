import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import { WorkspaceShell } from "../../../src/ui/WorkspaceShell";

describe("product session actions", () => {
  it("renders a generic native sign-out action in the shared product shell", () => {
    const { container } = render(
      <MemoryRouter initialEntries={["/operator"]}>
        <WorkspaceShell
          brand="OG"
          contentClassName="content"
          destinations={[{ label: "Operator", to: "/operator" }]}
          eyebrow="Office Graph"
          navigationLabel="Product"
          title="Operator"
        >
          <p>Content</p>
        </WorkspaceShell>
      </MemoryRouter>,
    );

    const button = screen.getByRole("button", { name: "Sign out" });
    const form = button.closest("form");

    expect(form).toHaveAttribute("action", "/auth/logout");
    expect(form).toHaveAttribute("method", "post");
    expect(form).toHaveTextContent(/^Sign out$/);
    expect(screen.getAllByRole("button")).toEqual([button]);
    expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
    expect(screen.queryByRole("listbox")).not.toBeInTheDocument();
    expect(container.querySelectorAll("input, select, textarea")).toHaveLength(0);
  });

  it("keeps caller-provided header actions alongside sign out", () => {
    render(
      <MemoryRouter>
        <WorkspaceShell
          brand="OG"
          contentClassName="content"
          destinations={[]}
          eyebrow="Office Graph"
          headerActions={<button type="button">Refresh</button>}
          navigationLabel="Product"
          title="Operator"
        >
          <p>Content</p>
        </WorkspaceShell>
      </MemoryRouter>,
    );

    expect(screen.getByRole("button", { name: "Refresh" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Sign out" })).toBeInTheDocument();
  });
});
