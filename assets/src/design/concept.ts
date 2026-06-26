export const conceptTokens = {
  colors: {
    appBackground: "#f7f9fb",
    surface: "#ffffff",
    surfaceSubtle: "#f1f6f7",
    border: "#dde5ea",
    borderStrong: "#c6d2d9",
    text: "#14202b",
    textMuted: "#667684",
    teal: "#0d8b95",
    amber: "#f59e0b",
    blue: "#2f8be6",
    green: "#19a340",
    red: "#d92d20"
  },
  radius: {
    control: "6px",
    panel: "6px"
  },
  typography: {
    family:
      'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    baseSize: "14px",
    smallSize: "12px",
    headingWeight: 650
  },
  layout: {
    sidebarWidth: "72px",
    inboxWidth: "380px",
    inspectorWidth: "392px",
    topbarHeight: "56px"
  }
} as const;

export const conceptComponentInventory = [
  "top-bar",
  "icon-sidebar",
  "inbox-table",
  "selected-item-header",
  "workflow-stepper",
  "detail-tabs",
  "detail-fields",
  "readiness-panel",
  "run-state-panel",
  "verification-panel",
  "activity-feed"
] as const;
