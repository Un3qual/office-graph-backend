import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { App } from "./App";

describe("operator console app shell", () => {
  it("renders the primary workbench regions", () => {
    render(<App />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Operator Console" })
    ).toBeInTheDocument();
    expect(screen.getByRole("navigation", { name: "Operator sections" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Inbox" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Item detail" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Run State" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Verification" })).toBeInTheDocument();
  });
});
