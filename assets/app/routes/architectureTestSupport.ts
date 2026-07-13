import ts from "typescript";

export function analyzeTypeScript(source: string, filename = "architecture-fixture.tsx") {
  const sourceFile = ts.createSourceFile(
    filename,
    source,
    ts.ScriptTarget.Latest,
    true,
    filename.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const identifiers = new Set<string>();
  const moduleSpecifiers = new Set<string>();
  const graphqlDocuments: string[] = [];
  const stringLiterals = new Set<string>();
  const stringCallArguments = new Map<string, string[][]>();
  const typeProperties = new Map<string, Map<string, string>>();
  const typedCalls = new Map<string, Set<string>>();

  const addModuleSpecifier = (expression: ts.Expression | undefined) => {
    if (expression && ts.isStringLiteralLike(expression)) {
      moduleSpecifiers.add(expression.text);
    } else if (expression) {
      moduleSpecifiers.add("<non-static dynamic import>");
    }
  };

  const visit = (node: ts.Node) => {
    if (ts.isIdentifier(node)) identifiers.add(node.text);
    if (ts.isStringLiteralLike(node)) stringLiterals.add(node.text);

    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
      addModuleSpecifier(node.moduleSpecifier);
    } else if (
      ts.isImportEqualsDeclaration(node) &&
      ts.isExternalModuleReference(node.moduleReference)
    ) {
      addModuleSpecifier(node.moduleReference.expression);
    } else if (ts.isCallExpression(node)) {
      if (node.expression.kind === ts.SyntaxKind.ImportKeyword) {
        addModuleSpecifier(node.arguments[0]);
      }

      if (ts.isIdentifier(node.expression) && node.typeArguments?.length) {
        const typeArguments = typedCalls.get(node.expression.text) ?? new Set<string>();
        for (const typeArgument of node.typeArguments) {
          typeArguments.add(typeArgument.getText(sourceFile));
        }
        typedCalls.set(node.expression.text, typeArguments);
      }

      if (ts.isIdentifier(node.expression)) {
        const calls = stringCallArguments.get(node.expression.text) ?? [];
        calls.push(
          node.arguments.map((argument) =>
            ts.isStringLiteralLike(argument) ? argument.text : argument.getText(sourceFile),
          ),
        );
        stringCallArguments.set(node.expression.text, calls);
      }
    } else if (ts.isTypeAliasDeclaration(node) && ts.isTypeLiteralNode(node.type)) {
      const properties = new Map<string, string>();
      for (const member of node.type.members) {
        if (!ts.isPropertySignature(member) || !member.type) continue;
        properties.set(
          member.name.getText(sourceFile).replaceAll(/["']/g, ""),
          member.type.getText(sourceFile),
        );
      }
      typeProperties.set(node.name.text, properties);
    } else if (
      ts.isTaggedTemplateExpression(node) &&
      ts.isIdentifier(node.tag) &&
      node.tag.text === "graphql"
    ) {
      graphqlDocuments.push(node.template.getText(sourceFile));
    }

    ts.forEachChild(node, visit);
  };

  visit(sourceFile);

  return {
    identifiers,
    moduleSpecifiers,
    graphqlDocuments,
    stringLiterals,
    stringCallArguments,
    typeProperties,
    typedCalls,
  };
}
