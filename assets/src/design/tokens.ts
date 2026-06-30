import { conceptTokens } from "./concept";

type TokenCategory = keyof typeof conceptTokens;

const tokenNames = {
  colors: {
    appBackground: "--og-color-app-background",
    surface: "--og-color-surface",
    surfaceSubtle: "--og-color-surface-subtle",
    border: "--og-color-border",
    borderStrong: "--og-color-border-strong",
    text: "--og-color-text",
    textMuted: "--og-color-text-muted",
    teal: "--og-color-teal",
    amber: "--og-color-amber",
    blue: "--og-color-blue",
    green: "--og-color-green",
    red: "--og-color-red"
  },
  radius: {
    control: "--og-radius-control",
    panel: "--og-radius-panel"
  },
  typography: {
    family: "--og-typography-family",
    baseSize: "--og-typography-base-size",
    smallSize: "--og-typography-small-size",
    headingWeight: "--og-typography-heading-weight"
  },
  layout: {
    sidebarWidth: "--og-layout-sidebar-width",
    inboxWidth: "--og-layout-inbox-width",
    inspectorWidth: "--og-layout-inspector-width",
    topbarHeight: "--og-layout-topbar-height"
  }
} as const satisfies {
  [Category in TokenCategory]: Record<keyof (typeof conceptTokens)[Category], string>;
};

export const tokenVar = {
  color: cssVarMap(tokenNames.colors),
  radius: cssVarMap(tokenNames.radius),
  typography: cssVarMap(tokenNames.typography),
  layout: cssVarMap(tokenNames.layout)
} as const;

export const designTokenCss = `:root {\n${Object.entries(tokenNames)
  .flatMap(([category, names]) =>
    Object.entries(names).map(
      ([key, variable]) =>
        `  ${variable}: ${conceptTokens[category as TokenCategory][
          key as keyof (typeof conceptTokens)[TokenCategory]
        ]};`
    )
  )
  .join("\n")}\n}`;

export function installDesignTokens(root: Document = document) {
  if (root.getElementById("office-graph-design-tokens")) {
    return;
  }

  const style = root.createElement("style");
  style.id = "office-graph-design-tokens";
  style.textContent = designTokenCss;
  root.head.prepend(style);
}

function cssVarMap<T extends Record<string, string>>(names: T) {
  return Object.fromEntries(
    Object.entries(names).map(([key, variable]) => [key, `var(${variable})`])
  ) as { [Key in keyof T]: `var(${T[Key]})` };
}
