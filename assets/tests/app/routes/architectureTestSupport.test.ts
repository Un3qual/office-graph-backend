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

  it("fails closed for identifier imports and folds concatenated static imports", () => {
    const facts = analyzeTypeScript(`
      const target = "./runtime-target";
      void import(target);
      void import("./routes/" + "safe-route");
    `);

    expect(facts.moduleSpecifiers).toContain("<non-static dynamic import>");
    expect(facts.moduleSpecifiers).toContain("./routes/safe-route");
  });

  it("derives GraphQL operation and selection facts without comment or string matches", () => {
    const facts = analyzeTypeScript(`
      const query = graphql\`
        # query CommentOnlyQuery { operatorInbox }
        query RealQuery {
          current: operatorWorkflowItems(first: 1) {
            # operatorInbox
            nodes { id note(value: "operatorInbox") }
          }
        }
      \`;
    `);

    expect(facts).toMatchObject({
      graphqlOperations: new Set(["RealQuery"]),
      graphqlFields: new Set(["operatorWorkflowItems", "nodes", "id", "note"]),
    });
  });

  it("canonicalizes aliased imported typed calls", () => {
    const facts = analyzeTypeScript(`
      import { useLazyLoadQuery as loadQuery } from "react-relay";
      const data = loadQuery<OperatorWorkflowRouteOperation>(query, variables);
    `);

    expect(facts.typedCalls.get("useLazyLoadQuery")).toEqual(
      new Set(["OperatorWorkflowRouteOperation"]),
    );
    expect(facts.typedCalls.has("loadQuery")).toBe(false);
  });
});
