import { readFileSync } from "node:fs";
import { join } from "node:path";
import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import { Badge } from "./Badge";
import { Button } from "./Button";
import { EmptyState } from "./EmptyState";
import { FormFeedback } from "./FormFeedback";
import { NavRail } from "./NavRail";
import { Panel, PanelRows, PaneHeader } from "./Panel";
import { TextField } from "./TextField";

describe("shared UI primitives", () => {
  it("renders generic presentation primitives without workflow vocabulary", () => {
    render(
      <>
        <Badge tone="green">Ready</Badge>
        <Button>Submit</Button>
        <Panel ariaLabel="Summary">
          <PaneHeader title="Summary" meta="2 items" />
          <PanelRows rows={[["Owner", "Ops"]]} />
        </Panel>
        <EmptyState title="Nothing here" tone="error">
          Try again later.
        </EmptyState>
        <TextField label="Search" placeholder="Search records" />
        <NavRail
          brand="OG"
          ariaLabel="Sections"
          items={[{ label: "Reports" }]}
        />
      </>
    );

    expect(screen.getByText("Ready")).toHaveAttribute("data-tone", "green");
    expect(screen.getByRole("button", { name: "Submit" })).toBeEnabled();
    expect(screen.getByRole("region", { name: "Summary" })).toHaveTextContent("OwnerOps");
    expect(screen.getByText("Nothing here")).toBeInTheDocument();
    expect(screen.getByLabelText("Search")).toHaveAttribute("placeholder", "Search records");
    expect(screen.getByRole("navigation", { name: "Sections" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Reports" })).toBeDisabled();
  });

  it("preserves render-prop class names on buttons", () => {
    render(
      <Button className={({ isDisabled }) => (isDisabled ? "state-disabled" : "state-enabled")} isDisabled>
        Stateful
      </Button>
    );

    expect(screen.getByRole("button", { name: "Stateful" })).toHaveClass(
      "ui-button",
      "ui-button-secondary",
      "state-disabled"
    );
  });

  it("links available destinations and disables unavailable destinations", () => {
    render(
      <MemoryRouter initialEntries={["/inbox"]}>
        <NavRail
          brand="OG"
          ariaLabel="Sections"
          items={[
            { label: "Inbox", to: "/inbox" },
            { label: "Activity", to: "/activity" },
            { label: "Reports" }
          ]}
        />
      </MemoryRouter>
    );

    expect(screen.getByRole("link", { name: "Inbox" })).toHaveAttribute("href", "/inbox");
    expect(screen.getByRole("link", { name: "Inbox" })).toHaveAttribute(
      "aria-current",
      "page"
    );
    expect(screen.getByRole("link", { name: "Activity" })).not.toHaveAttribute(
      "aria-current"
    );
    expect(screen.getByRole("button", { name: "Reports" })).toBeDisabled();
    expect(screen.queryByRole("link", { name: "Reports" })).not.toBeInTheDocument();
  });

  it("keeps product navigation available in compact layouts", () => {
    const styles = readFileSync(join(process.cwd(), "src/styles/global.css"), "utf8");
    const compactBreakpoint = styles.indexOf("@media (max-width: 980px)");

    expect(compactBreakpoint).toBeGreaterThan(-1);

    const compactStyles = styles.slice(compactBreakpoint);

    expect(compactStyles).not.toMatch(
      /\.ui-nav-rail\s*\{[^}]*display:\s*none\s*;/
    );
    expect(compactStyles).toMatch(/\.ui-nav-rail\s*\{[^}]*display:\s*grid\s*;/);
    expect(compactStyles).toMatch(
      /\.ui-nav-rail nav\s*\{[^}]*overflow-x:\s*auto\s*;/
    );
  });

  it("renders pending and caller-owned form feedback accessibly", () => {
    const { rerender } = render(
      <FormFeedback pendingMessage="Saving changes." />
    );

    expect(screen.getByRole("status")).toHaveTextContent("Saving changes.");

    rerender(
      <FormFeedback
        feedback={{
          kind: "field",
          field: "title",
          message: "A title is required."
        }}
      />
    );

    expect(screen.getByRole("alert")).toHaveTextContent("A title is required.");
    expect(screen.getByRole("alert")).toHaveAttribute("data-kind", "field");
    expect(screen.getByRole("alert")).toHaveAttribute("data-field", "title");

    rerender(
      <FormFeedback
        feedback={{ kind: "conflict", message: "Refresh before retrying." }}
      />
    );

    expect(screen.getByRole("alert")).toHaveTextContent("Refresh before retrying.");
    expect(screen.getByRole("alert")).toHaveAttribute("data-kind", "conflict");
  });
});
