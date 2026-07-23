import { existsSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
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

export function routeRegistrationOffenders(
  source: string,
  {
    canonicalPath,
    ownedModulePrefix,
  }: {
    canonicalPath: string;
    ownedModulePrefix: string;
  },
) {
  const routeCalls = analyzeTypeScript(source, "routes.ts").stringCallArguments.get("route") ?? [];
  const ownedRegistrations = routeCalls.filter(
    ([, target]) => target === ownedModulePrefix || target.startsWith(`${ownedModulePrefix}/`),
  );
  const canonicalRegistrations = ownedRegistrations.filter(([path]) => path === canonicalPath);
  const offenders = ownedRegistrations
    .filter(([path]) => path !== canonicalPath)
    .map(([path, target]) => `${path} targets runs-owned module "${target}"`);

  if (canonicalRegistrations.length !== 1) {
    offenders.unshift(`canonical ${canonicalPath} route must target one owned module`);
  }

  return offenders;
}

export function bareModuleSpecifierOffenders(
  specifiers: Iterable<string>,
  allowedSpecifiers: ReadonlySet<string>,
) {
  return [...specifiers]
    .filter(
      (specifier) =>
        specifier === "<non-static dynamic import>" ||
        (!specifier.startsWith(".") &&
          !specifier.startsWith("/") &&
          !specifier.startsWith("node:") &&
          !allowedSpecifiers.has(specifier)),
    )
    .sort();
}

export function normalizeModuleSpecifier(specifier: string, filename: string, projectRoot: string) {
  if (!specifier.startsWith(".")) return specifier;

  return relative(projectRoot, resolve(dirname(filename), specifier)).replaceAll("\\", "/");
}

export function localDependencyFiles(entries: string[]) {
  const pending = [...entries];
  const visited = new Set<string>();

  while (pending.length > 0) {
    const file = pending.pop();
    if (!file || visited.has(file)) continue;

    visited.add(file);
    const source = readFileSync(file, "utf8");

    for (const { fileName } of ts.preProcessFile(source, true, true).importedFiles) {
      if (!fileName.startsWith(".")) continue;

      const dependency = resolveSourceFile(resolve(dirname(file), fileName));
      if (dependency && !visited.has(dependency)) pending.push(dependency);
    }
  }

  return [...visited];
}

export function emittedClassNames(source: string, filename: string) {
  const sourceFile = ts.createSourceFile(
    filename,
    source,
    ts.ScriptTarget.Latest,
    true,
    filename.endsWith("x") ? ts.ScriptKind.TSX : ts.ScriptKind.TS,
  );
  const names = new Set<string>();

  const addTokens = (value: string) => {
    for (const token of value.split(/\s+/)) {
      if (/^[a-z][\w-]*$/i.test(token)) names.add(token);
    }
  };

  const collectExpression = (expression: ts.Expression, passThrough = new Set<string>()) => {
    if (ts.isStringLiteralLike(expression)) {
      addTokens(expression.text);
      return;
    }

    if (ts.isTemplateExpression(expression)) {
      for (const value of finiteTemplateValues(expression, sourceFile)) addTokens(value);
      return;
    }

    if (ts.isConditionalExpression(expression)) {
      collectExpression(expression.whenTrue, passThrough);
      collectExpression(expression.whenFalse, passThrough);
      return;
    }

    if (ts.isArrowFunction(expression) && !ts.isBlock(expression.body)) {
      const arrowPassThrough = new Set(passThrough);
      for (const parameter of expression.parameters) {
        if (ts.isIdentifier(parameter.name)) arrowPassThrough.add(parameter.name.text);
        if (ts.isObjectBindingPattern(parameter.name)) {
          for (const binding of parameter.name.elements) {
            if (ts.isIdentifier(binding.name)) arrowPassThrough.add(binding.name.text);
          }
        }
      }
      collectExpression(expression.body, arrowPassThrough);
      return;
    }

    if (ts.isArrayLiteralExpression(expression)) {
      for (const element of expression.elements) {
        if (ts.isSpreadElement(element)) unsupportedClassExpression(element, sourceFile);
        collectExpression(element, passThrough);
      }
      return;
    }

    if (ts.isParenthesizedExpression(expression)) {
      collectExpression(expression.expression, passThrough);
      return;
    }

    if (ts.isIdentifier(expression)) {
      if (expression.text === "undefined" || passThrough.has(expression.text)) return;
      unsupportedClassExpression(expression, sourceFile);
    }

    if (expression.kind === ts.SyntaxKind.NullKeyword) return;

    if (ts.isCallExpression(expression)) {
      if (
        ts.isIdentifier(expression.expression) &&
        expression.expression.text === "composeRenderProps" &&
        expression.arguments.length === 2 &&
        ts.isIdentifier(expression.arguments[0]) &&
        passThrough.has(expression.arguments[0].text) &&
        ts.isArrowFunction(expression.arguments[1])
      ) {
        collectExpression(expression.arguments[1], passThrough);
        return;
      }

      if (
        ts.isPropertyAccessExpression(expression.expression) &&
        expression.expression.name.text === "filter" &&
        expression.arguments.length === 1 &&
        ts.isIdentifier(expression.arguments[0]) &&
        expression.arguments[0].text === "Boolean"
      ) {
        collectExpression(expression.expression.expression, passThrough);
        return;
      }

      if (
        ts.isPropertyAccessExpression(expression.expression) &&
        expression.expression.name.text === "join" &&
        expression.arguments.length === 1 &&
        ts.isStringLiteralLike(expression.arguments[0]) &&
        expression.arguments[0].text === " "
      ) {
        collectExpression(expression.expression.expression, passThrough);
        return;
      }
    }

    unsupportedClassExpression(expression, sourceFile);
  };

  walk(sourceFile, (node) => {
    const attributeName = ts.isJsxAttribute(node) ? node.name.getText(sourceFile) : null;

    if (
      ts.isJsxAttribute(node) &&
      (attributeName === "className" || attributeName?.endsWith("ClassName")) &&
      node.initializer
    ) {
      if (ts.isStringLiteral(node.initializer)) {
        addTokens(node.initializer.text);
      } else if (ts.isJsxExpression(node.initializer) && node.initializer.expression) {
        collectExpression(node.initializer.expression, destructuredClassNameParameters(node));
      } else {
        throw new Error(`Unsupported ${attributeName} initializer in ${filename}`);
      }
    }
  });

  return [...names];
}

export function stylesheetOwnerClasses(styles: string) {
  const withoutComments = styles.replace(/\/\*[\s\S]*?\*\//g, "");
  const owners = new Set<string>();

  for (const match of withoutComments.matchAll(/(?:^|[{}])\s*([^@{}\s][^{}]*?)\s*\{/g)) {
    const selectorList = match[1];
    for (const selector of selectorList.split(",")) {
      const owner = selector.match(/\.([a-z_][\w-]*)/i)?.[1];
      if (owner) owners.add(owner);
    }
  }

  return owners;
}

export function unownedClassNames(classes: Iterable<string>, owners: ReadonlySet<string>) {
  return [...new Set(classes)].filter((className) => !owners.has(className)).sort();
}

function resolveSourceFile(path: string) {
  for (const candidate of [
    path,
    `${path}.ts`,
    `${path}.tsx`,
    join(path, "index.ts"),
    join(path, "index.tsx"),
  ]) {
    if (existsSync(candidate)) return candidate;
  }

  return null;
}

function finiteTemplateValues(template: ts.TemplateExpression, sourceFile: ts.SourceFile) {
  let values = [template.head.text];

  for (const span of template.templateSpans) {
    if (!ts.isConditionalExpression(span.expression)) {
      throw new Error(
        `Unsupported dynamic className template span: ${span.expression.getText(sourceFile)}`,
      );
    }

    const spanValues = [span.expression.whenTrue, span.expression.whenFalse].flatMap((branch) =>
      ts.isStringLiteralLike(branch) ? [branch.text] : [],
    );
    if (spanValues.length !== 2) {
      throw new Error(
        `Unsupported dynamic className template span: ${span.expression.getText(sourceFile)}`,
      );
    }

    values = values.flatMap((prefix) =>
      spanValues.map((spanValue) => `${prefix}${spanValue}${span.literal.text}`),
    );
  }

  return values;
}

function destructuredClassNameParameters(node: ts.Node) {
  let current = node.parent;
  while (current && !ts.isFunctionLike(current)) current = current.parent;

  const parameters = new Set<string>();
  for (const parameter of current?.parameters ?? []) {
    if (!ts.isObjectBindingPattern(parameter.name)) continue;

    for (const binding of parameter.name.elements) {
      if (
        ts.isIdentifier(binding.name) &&
        (binding.name.text === "className" || binding.name.text.endsWith("ClassName"))
      ) {
        parameters.add(binding.name.text);
      }
    }
  }

  return parameters;
}

function unsupportedClassExpression(expression: ts.Node, sourceFile: ts.SourceFile): never {
  throw new Error(`Unsupported className expression: ${expression.getText(sourceFile)}`);
}

function walk(node: ts.Node, visit: (node: ts.Node) => void) {
  visit(node);
  ts.forEachChild(node, (child) => walk(child, visit));
}
