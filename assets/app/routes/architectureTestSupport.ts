import { parse, visit as visitGraphQL } from "graphql";
import ts from "typescript";

export function analyzeTypeScript(source: string, filename = "architecture-fixture.tsx") {
  const sourceFile = ts.createSourceFile(
    filename,
    source,
    ts.ScriptTarget.Latest,
    true,
    filename.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const importedNames = importedCanonicalNames(sourceFile);
  const identifiers = new Set<string>();
  const moduleSpecifiers = new Set<string>();
  const graphqlOperations = new Set<string>();
  const graphqlFields = new Set<string>();
  const graphqlParseErrors: string[] = [];
  const stringLiterals = new Set<string>();
  const stringCallArguments = new Map<string, string[][]>();
  const typeProperties = new Map<string, Map<string, string>>();
  const typedCalls = new Map<string, Set<string>>();

  const addModuleSpecifier = (expression: ts.Expression | undefined) => {
    const specifier = expression ? staticStringValue(expression) : null;
    if (specifier !== null) {
      moduleSpecifiers.add(specifier);
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
        const callName = importedNames.get(node.expression.text) ?? node.expression.text;
        const typeArguments = typedCalls.get(callName) ?? new Set<string>();
        for (const typeArgument of node.typeArguments) {
          typeArguments.add(typeArgument.getText(sourceFile));
        }
        typedCalls.set(callName, typeArguments);
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
      if (ts.isNoSubstitutionTemplateLiteral(node.template)) {
        try {
          visitGraphQL(parse(node.template.text), {
            Field(field) {
              graphqlFields.add(field.name.value);
            },
            OperationDefinition(operation) {
              if (operation.name) graphqlOperations.add(operation.name.value);
            },
          });
        } catch (error) {
          graphqlParseErrors.push(
            error instanceof Error ? error.message : "Unable to parse GraphQL document.",
          );
        }
      } else {
        graphqlParseErrors.push("GraphQL documents must be static template literals.");
      }
    }

    ts.forEachChild(node, visit);
  };

  visit(sourceFile);

  return {
    identifiers,
    moduleSpecifiers,
    graphqlOperations,
    graphqlFields,
    graphqlParseErrors,
    stringLiterals,
    stringCallArguments,
    typeProperties,
    typedCalls,
  };
}

function importedCanonicalNames(sourceFile: ts.SourceFile) {
  const names = new Map<string, string>();

  const visit = (node: ts.Node) => {
    if (ts.isImportSpecifier(node)) {
      names.set(node.name.text, node.propertyName?.text ?? node.name.text);
    }
    ts.forEachChild(node, visit);
  };

  visit(sourceFile);
  return names;
}

function staticStringValue(expression: ts.Expression): string | null {
  if (ts.isStringLiteralLike(expression)) return expression.text;
  if (ts.isParenthesizedExpression(expression)) return staticStringValue(expression.expression);

  if (
    ts.isBinaryExpression(expression) &&
    expression.operatorToken.kind === ts.SyntaxKind.PlusToken
  ) {
    const left = staticStringValue(expression.left);
    const right = staticStringValue(expression.right);
    return left === null || right === null ? null : left + right;
  }

  return null;
}
