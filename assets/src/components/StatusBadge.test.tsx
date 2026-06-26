import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { StatusBadge } from "./StatusBadge";

describe("StatusBadge", () => {
  it("renders a formatted workflow status with its visual tone", () => {
    render(<StatusBadge status="pending_triage" />);

    const badge = screen.getByText("Pending triage");
    expect(badge).toHaveAttribute("data-tone", "teal");
  });
});
