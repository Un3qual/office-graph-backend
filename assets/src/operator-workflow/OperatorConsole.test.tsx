import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { OperatorConsole } from "./OperatorConsole";
import {
  sampleInbox,
  samplePacketReadiness,
  sampleRunState,
  sampleVerificationOutcome
} from "./fixtures";
import type { OperatorWorkflowItem } from "./api";

describe("OperatorConsole", () => {
  it("loads the inbox, selected item, readiness, run state, and verification", async () => {
    const item = selectedItemFixture();
    const api = {
      loadInbox: vi.fn(async () => ({
        ...sampleInbox,
        rows: [item, { ...sampleInbox.rows[0], normalized_event_id: "evt_2" }]
      })),
      loadItem: vi.fn(async () => item),
      loadPacketReadiness: vi.fn(async () => samplePacketReadiness),
      loadRunState: vi.fn(async () => sampleRunState),
      loadVerificationOutcome: vi.fn(async () => sampleVerificationOutcome)
    };

    render(<OperatorConsole api={api} />);

    expect(screen.getByText("Loading inbox...")).toBeInTheDocument();
    expect(await screen.findByRole("button", { name: /evt_1/i })).toHaveAttribute(
      "aria-current",
      "true"
    );
    expect(await screen.findByRole("heading", { name: "evt_1" })).toBeInTheDocument();
    expect(screen.getAllByText("Ready for packet").length).toBeGreaterThan(0);
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "Packet ready"
    );
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
      "Awaiting evidence acceptance"
    );
    expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
      "Awaiting evidence acceptance"
    );
    expect(screen.getByRole("button", { name: /evt_1/i })).toHaveTextContent("Watermark op_123");
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "normalized_intake_event: evt_1"
    );
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "Revision trace"
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "None"
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "Run console verification"
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "AutonomyNone"
    );
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
      "Evidence candidates"
    );
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent("Fresh");
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent("Owner attested");
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
      "manual:operator-console"
    );
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
      "Operator console evidence is ready."
    );
    expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
      "Owner acceptance"
    );
    expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
      "missing_accepted_evidence"
    );

    expect(api.loadItem).toHaveBeenCalledWith("evt_1");
    expect(api.loadPacketReadiness).toHaveBeenCalledWith(
      {
        source_graph_item_ids: ["graph_1"],
        verification_check_ids: ["check_1"]
      }
    );
    expect(api.loadRunState).toHaveBeenCalledWith("run_1");
    expect(api.loadVerificationOutcome).toHaveBeenCalledWith("run_1");
  });

  it("requests readiness blockers even when graph links are missing", async () => {
    const item = { ...selectedItemFixture(), graph_links: [] };
    const blockedReadiness = {
      ...samplePacketReadiness,
      ready: false,
      status: "blocked",
      allowed_next_actions: [],
      blocker_reasons: [
        "missing_objective",
        "missing_context_summary",
        "missing_requirements",
        "missing_success_criteria",
        "missing_source_graph_items",
        "missing_verification_checks",
        "unsupported_autonomy_posture"
      ],
      source_links: [],
      required_checks: []
    };
    const api = {
      loadInbox: vi.fn(async () => ({ ...sampleInbox, rows: [item] })),
      loadItem: vi.fn(async () => item),
      loadPacketReadiness: vi.fn(async () => blockedReadiness),
      loadRunState: vi.fn(),
      loadVerificationOutcome: vi.fn()
    };

    render(<OperatorConsole api={api} />);

    expect(await screen.findByRole("heading", { name: "evt_1" })).toBeInTheDocument();
    expect(api.loadPacketReadiness).toHaveBeenCalledWith(
      {
        source_graph_item_ids: [],
        verification_check_ids: []
      }
    );
    expect(screen.getByRole("region", { name: "Packet Readiness" })).toHaveTextContent(
      "missing_objective, missing_context_summary, missing_requirements, missing_success_criteria, missing_source_graph_items, missing_verification_checks, unsupported_autonomy_posture"
    );
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
      "No run linked yet."
    );
    expect(api.loadRunState).not.toHaveBeenCalled();
    expect(api.loadVerificationOutcome).not.toHaveBeenCalled();
  });

  it("leaves run panels idle until the backend provides a run link", async () => {
    const item = {
      ...selectedItemFixture(),
      graph_links: selectedItemFixture().graph_links.filter((link) => link.type !== "work_run")
    };
    const api = {
      loadInbox: vi.fn(async () => ({ ...sampleInbox, rows: [item] })),
      loadItem: vi.fn(async () => item),
      loadPacketReadiness: vi.fn(async () => samplePacketReadiness),
      loadRunState: vi.fn(),
      loadVerificationOutcome: vi.fn()
    };

    render(<OperatorConsole api={api} />);

    expect(await screen.findByRole("heading", { name: "evt_1" })).toBeInTheDocument();
    expect(api.loadPacketReadiness).toHaveBeenCalled();
    expect(screen.getByRole("region", { name: "Run State" })).toHaveTextContent(
      "No run linked yet."
    );
    expect(screen.getByRole("region", { name: "Verification" })).toHaveTextContent(
      "No verification outcome selected."
    );
    expect(api.loadRunState).not.toHaveBeenCalled();
    expect(api.loadVerificationOutcome).not.toHaveBeenCalled();
  });

  it("selects another inbox row", async () => {
    const first = selectedItemFixture();
    const second = { ...selectedItemFixture(), normalized_event_id: "evt_2" };
    const api = {
      loadInbox: vi.fn(async () => ({ ...sampleInbox, rows: [first, second] })),
      loadItem: vi.fn(async (id: string) => (id === "evt_2" ? second : first)),
      loadPacketReadiness: vi.fn(async () => samplePacketReadiness),
      loadRunState: vi.fn(async () => sampleRunState),
      loadVerificationOutcome: vi.fn(async () => sampleVerificationOutcome)
    };

    render(<OperatorConsole api={api} />);

    fireEvent.click(await screen.findByRole("button", { name: /evt_2/i }));

    await waitFor(() => expect(api.loadItem).toHaveBeenLastCalledWith("evt_2"));
    expect(await screen.findByRole("heading", { name: "evt_2" })).toBeInTheDocument();
  });

  it("shows an empty inbox state without enabled workflow commands", async () => {
    const api = {
      loadInbox: vi.fn(async () => ({ ...sampleInbox, empty: true, rows: [] })),
      loadItem: vi.fn(),
      loadPacketReadiness: vi.fn(),
      loadRunState: vi.fn(),
      loadVerificationOutcome: vi.fn()
    };

    render(<OperatorConsole api={api} />);

    expect(await screen.findByText("No operator workflow items.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /apply/i })).not.toBeInTheDocument();
  });

  it("keeps context visible when inbox loading fails", async () => {
    const api = {
      loadInbox: vi.fn(async () => {
        throw new Error("Network unavailable");
      }),
      loadItem: vi.fn(),
      loadPacketReadiness: vi.fn(),
      loadRunState: vi.fn(),
      loadVerificationOutcome: vi.fn()
    };

    render(<OperatorConsole api={api} />);

    expect(await screen.findByText("Network unavailable")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Inbox" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Item detail" })).toHaveTextContent(
      "No item selected"
    );
  });
});

function selectedItemFixture(): OperatorWorkflowItem {
  return {
    ...sampleInbox.rows[0],
    status: "ready_for_packet",
    allowed_next_actions: ["prepare_packet"],
    graph_links: [
      {
        type: "verification_check",
        id: "check_1",
        graph_item_id: "graph_1",
        title: "Run console verification",
        state: "open"
      },
      {
        type: "work_run",
        id: "run_1",
        graph_item_id: null,
        title: "Console verification run",
        state: "running"
      }
    ]
  };
}
