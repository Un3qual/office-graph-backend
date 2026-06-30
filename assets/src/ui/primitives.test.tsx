import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { Badge } from "./Badge";
import { Button } from "./Button";
import { EmptyState } from "./EmptyState";
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
          items={[
            { label: "Inbox", state: "current" },
            { label: "Reports", state: "unavailable" }
          ]}
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
});
