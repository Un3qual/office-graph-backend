import { describe, expect, it } from "vitest";
import { analyzeTypeScript } from "./architectureTestSupport";

describe("TypeScript architecture facts", () => {
  it("ignores comments and string copy while retaining aliased executable imports", () => {
    const facts = analyzeTypeScript(`
      // useEffect and fetchQuery are discussion-only here.
      const copy = "useRelayEnvironment";
      import { fetchQuery as runQuery } from "react-relay";
      runQuery(environment, query, variables);
    `);

    expect(facts.identifiers).not.toContain("useEffect");
    expect(facts.identifiers).not.toContain("useRelayEnvironment");
    expect(facts.identifiers).toContain("fetchQuery");
    expect(facts.identifiers).toContain("runQuery");
  });
});
