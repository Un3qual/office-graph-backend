import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { installDesignTokens } from "./design/tokens";

const root = document.getElementById("operator-console-root");

if (root) {
  installDesignTokens();

  createRoot(root).render(
    <StrictMode>
      <App />
    </StrictMode>
  );
}
