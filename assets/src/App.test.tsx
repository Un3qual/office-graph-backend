import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { App } from "./App";

describe("operator console app shell", () => {
  it("renders the primary workbench regions", async () => {
    render(<App api={emptyApi()} />);

    expect(
      screen.getByRole("heading", { level: 1, name: "Operator Console" })
    ).toBeInTheDocument();
    expect(screen.getByRole("navigation", { name: "Operator sections" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Inbox" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Item detail" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Run State" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Verification" })).toBeInTheDocument();
    expect(await screen.findByText("No operator workflow items.")).toBeInTheDocument();
  });
});

function emptyApi() {
  return {
    loadInbox: async () => ({
      type: "operator_inbox" as const,
      empty: true,
      source_watermark: null,
      rows: []
    }),
    loadItem: async () => {
      throw new Error("No item expected");
    },
    loadPacketReadiness: async () => {
      throw new Error("No packet expected");
    },
    loadRunState: async () => {
      throw new Error("No run expected");
    },
    loadVerificationOutcome: async () => {
      throw new Error("No verification expected");
    }
  };
}
