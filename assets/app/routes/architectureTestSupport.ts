import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join, posix, relative, resolve } from "node:path";
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
          node.arguments.map(
            (argument) => staticStringValue(argument) ?? argument.getText(sourceFile),
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
  if (ts.isTemplateExpression(expression)) {
    let value = expression.head.text;

    for (const span of expression.templateSpans) {
      const spanValue = staticStringValue(span.expression);
      if (spanValue === null) return null;
      value += spanValue + span.literal.text;
    }

    return value;
  }

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

type RouteConfigHelperKind = "index" | "layout" | "prefix" | "relative" | "route";

type RouteConfigHelper =
  | { kind: "index"; relativeDirectory?: string | null }
  | { kind: "layout"; relativeDirectory?: string | null }
  | { kind: "prefix"; relativeDirectory?: string | null }
  | { kind: "relative" }
  | { kind: "route"; relativeDirectory?: string | null };

type RouteRegistrationHelper = Exclude<RouteConfigHelper, { kind: "prefix" | "relative" }>;

type RouteRegistration = {
  kind: RouteRegistrationHelper["kind"];
  path: string | null;
  target: string;
  targetIdentity: string;
};

export function analyzeRouteConfig(
  source: string,
  {
    canonicalPath,
    ownedModulePrefix,
  }: {
    canonicalPath: string;
    ownedModulePrefix: string;
  },
) {
  const sourceFile = ts.createSourceFile(
    "routes.ts",
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const registrations: RouteRegistration[] = [];
  const extractionOffenders: string[] = [];
  const routeHelpers = routeConfigHelpers(sourceFile);
  const defaultExports = sourceFile.statements.filter(
    (statement): statement is ts.ExportAssignment =>
      ts.isExportAssignment(statement) && !statement.isExportEquals,
  );
  const defaultRouteConfig =
    defaultExports.length === 1 ? unwrapRouteConfigExpression(defaultExports[0].expression) : null;

  if (!defaultRouteConfig) {
    const detail =
      defaultExports.length === 1 ? `: ${defaultExports[0].expression.getText(sourceFile)}` : "";
    return {
      canonicalTarget: null,
      offenders: [`default route config must be a static registration array${detail}`],
      registrations,
    };
  }

  collectRouteConfigArray(defaultRouteConfig, "");

  const ownedModuleIdentity = routeModuleIdentity(ownedModulePrefix);
  const canonicalModuleIdentity = routeModuleIdentity(`${ownedModulePrefix}/route.tsx`);
  const ownedRegistrations = registrations.filter(
    ({ targetIdentity }) =>
      targetIdentity === ownedModuleIdentity ||
      targetIdentity.startsWith(`${ownedModuleIdentity}/`),
  );
  const canonicalRegistrations = ownedRegistrations.filter(
    ({ path, targetIdentity }) =>
      path === canonicalPath && targetIdentity === canonicalModuleIdentity,
  );
  const canonicalTarget =
    canonicalRegistrations.length === 1 ? canonicalRegistrations[0].target : null;

  if (extractionOffenders.length > 0) {
    return {
      canonicalTarget,
      offenders: extractionOffenders,
      registrations,
    };
  }

  const offenders = ownedRegistrations
    .filter(
      ({ path, targetIdentity }) =>
        path !== canonicalPath || targetIdentity !== canonicalModuleIdentity,
    )
    .map(
      ({ kind, path, target }) => `${path ?? `<${kind}>`} targets runs-owned module "${target}"`,
    );

  if (canonicalRegistrations.length !== 1) {
    offenders.unshift(`canonical ${canonicalPath} route must target one owned module`);
  }

  return { canonicalTarget, offenders, registrations };

  function collectRouteConfigArray(array: ts.ArrayLiteralExpression, pathPrefix: string) {
    for (const element of array.elements) {
      if (ts.isSpreadElement(element)) {
        const spreadCall = unwrapCallExpression(element.expression);
        const spreadHelper = spreadCall ? calledRouteHelper(spreadCall, routeHelpers) : null;

        if (spreadCall && spreadHelper?.kind === "prefix") {
          collectPrefix(spreadCall, pathPrefix);
        } else {
          extractionOffenders.push(
            `unrecognized route registration: ${element.getText(sourceFile)}`,
          );
        }
        continue;
      }

      const call = unwrapCallExpression(element);
      const helper = call ? calledRouteHelper(call, routeHelpers) : null;

      if (!call || !helper || helper.kind === "prefix" || helper.kind === "relative") {
        extractionOffenders.push(`unrecognized route registration: ${element.getText(sourceFile)}`);
        continue;
      }

      collectRegistration(call, helper, pathPrefix);
    }
  }

  function collectRegistration(
    call: ts.CallExpression,
    helper: RouteRegistrationHelper,
    pathPrefix: string,
  ) {
    if (helper.kind === "route") {
      const [pathExpression, targetExpression, optionsOrChildren, explicitChildren] =
        call.arguments;
      const routePath = staticRoutePath(pathExpression);
      const target = staticRouteTarget(targetExpression, helper);

      if (!routePath.static) {
        extractionOffenders.push(
          `route call has a non-static path: ${pathExpression?.getText(sourceFile) ?? "<missing>"}`,
        );
      }
      if (target === null) {
        extractionOffenders.push(
          `route call has a non-static target: ${targetExpression?.getText(sourceFile) ?? "<missing>"}`,
        );
      }
      if (routePath.static && target !== null) {
        registrations.push({
          kind: "route",
          path: routePath.value === null ? null : prefixedRoutePath(pathPrefix, routePath.value),
          target,
          targetIdentity: routeModuleIdentity(target),
        });
      }

      const childPrefix =
        routePath.static && routePath.value !== null
          ? prefixedRoutePath(pathPrefix, routePath.value)
          : pathPrefix;
      collectOptionalChildren("route", optionsOrChildren, explicitChildren, childPrefix);
      return;
    }

    const [targetExpression, optionsOrChildren, explicitChildren] = call.arguments;
    const target = staticRouteTarget(targetExpression, helper);

    if (target === null) {
      extractionOffenders.push(
        `${helper.kind} call has a non-static target: ${targetExpression?.getText(sourceFile) ?? "<missing>"}`,
      );
    } else {
      registrations.push({
        kind: helper.kind,
        path: helper.kind === "index" && pathPrefix ? pathPrefix : null,
        target,
        targetIdentity: routeModuleIdentity(target),
      });
    }

    if (helper.kind === "layout") {
      collectOptionalChildren("layout", optionsOrChildren, explicitChildren, pathPrefix);
    }
  }

  function collectOptionalChildren(
    helperName: "layout" | "route",
    optionsOrChildren: ts.Expression | undefined,
    explicitChildren: ts.Expression | undefined,
    pathPrefix: string,
  ) {
    if (!optionsOrChildren && !explicitChildren) return;

    const inlineChildren = optionsOrChildren
      ? unwrapRouteConfigExpression(optionsOrChildren)
      : null;
    if (inlineChildren) {
      if (explicitChildren) {
        extractionOffenders.push(
          `${helperName} call has ambiguous children: ${explicitChildren.getText(sourceFile)}`,
        );
      } else {
        collectRouteConfigArray(inlineChildren, pathPrefix);
      }
      return;
    }

    if (optionsOrChildren && !ts.isObjectLiteralExpression(unwrapExpression(optionsOrChildren))) {
      extractionOffenders.push(
        `${helperName} call has non-static options or children: ${optionsOrChildren.getText(sourceFile)}`,
      );
      return;
    }

    if (!explicitChildren) return;

    const children = unwrapRouteConfigExpression(explicitChildren);
    if (!children) {
      extractionOffenders.push(
        `${helperName} call has non-static children: ${explicitChildren.getText(sourceFile)}`,
      );
      return;
    }

    collectRouteConfigArray(children, pathPrefix);
  }

  function collectPrefix(call: ts.CallExpression, pathPrefix: string) {
    const [prefixExpression, routesExpression] = call.arguments;
    const prefixPath = prefixExpression ? staticStringValue(prefixExpression) : null;
    const routes = routesExpression ? unwrapRouteConfigExpression(routesExpression) : null;

    if (prefixPath === null) {
      extractionOffenders.push(
        `prefix call has a non-static path: ${prefixExpression?.getText(sourceFile) ?? "<missing>"}`,
      );
    }
    if (!routes) {
      extractionOffenders.push(
        `prefix call has non-static routes: ${routesExpression?.getText(sourceFile) ?? "<missing>"}`,
      );
    }
    if (prefixPath !== null && routes) {
      collectRouteConfigArray(routes, prefixedRoutePath(pathPrefix, prefixPath));
    }
  }
}

export function routeRegistrationOffenders(
  source: string,
  registration: {
    canonicalPath: string;
    ownedModulePrefix: string;
  },
) {
  return analyzeRouteConfig(source, registration).offenders;
}

function routeConfigHelpers(sourceFile: ts.SourceFile) {
  const helpers = new Map<string, RouteConfigHelper>();

  for (const statement of sourceFile.statements) {
    if (
      !ts.isImportDeclaration(statement) ||
      !ts.isStringLiteralLike(statement.moduleSpecifier) ||
      statement.moduleSpecifier.text !== "@react-router/dev/routes" ||
      !statement.importClause?.namedBindings ||
      !ts.isNamedImports(statement.importClause.namedBindings)
    ) {
      continue;
    }

    for (const specifier of statement.importClause.namedBindings.elements) {
      if (statement.importClause.isTypeOnly || specifier.isTypeOnly) continue;

      const importedName = specifier.propertyName?.text ?? specifier.name.text;
      if (!isRouteConfigHelperKind(importedName)) continue;
      helpers.set(specifier.name.text, { kind: importedName });
    }
  }

  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue;

    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isObjectBindingPattern(declaration.name) || !declaration.initializer) {
        continue;
      }

      const initializer = unwrapCallExpression(declaration.initializer);
      const relativeHelper = initializer ? calledRouteHelper(initializer, helpers) : null;
      if (!initializer || relativeHelper?.kind !== "relative") continue;

      const directoryExpression = initializer.arguments[0];
      const relativeDirectory = directoryExpression ? staticStringValue(directoryExpression) : null;

      for (const element of declaration.name.elements) {
        if (element.dotDotDotToken || !ts.isIdentifier(element.name)) {
          continue;
        }

        const importedName = element.propertyName
          ? staticPropertyName(element.propertyName)
          : element.name.text;
        if (!importedName || !isRelativeRouteConfigHelperKind(importedName)) continue;

        helpers.set(element.name.text, {
          kind: importedName,
          relativeDirectory,
        });
      }
    }
  }

  return helpers;
}

function isRouteConfigHelperKind(value: string): value is RouteConfigHelperKind {
  return (
    value === "index" ||
    value === "layout" ||
    value === "prefix" ||
    value === "relative" ||
    value === "route"
  );
}

function isRelativeRouteConfigHelperKind(
  value: string,
): value is Exclude<RouteConfigHelperKind, "relative"> {
  return value === "index" || value === "layout" || value === "prefix" || value === "route";
}

function calledRouteHelper(
  call: ts.CallExpression,
  helpers: ReadonlyMap<string, RouteConfigHelper>,
) {
  return ts.isIdentifier(call.expression) ? (helpers.get(call.expression.text) ?? null) : null;
}

function staticRouteTarget(expression: ts.Expression | undefined, helper: RouteRegistrationHelper) {
  if (!expression) return null;

  const target = staticStringValue(expression);
  if (target === null || helper.relativeDirectory === null) return null;
  if (helper.relativeDirectory === undefined) return target;

  const appRelativeTarget = relative(
    resolve(process.cwd(), "app"),
    resolve(helper.relativeDirectory, target),
  ).replaceAll("\\", "/");

  return appRelativeTarget.startsWith(".") ? appRelativeTarget : `./${appRelativeTarget}`;
}

function staticRoutePath(
  expression: ts.Expression | undefined,
): { static: true; value: string | null } | { static: false } {
  if (!expression) return { static: false };

  const unwrapped = unwrapExpression(expression);
  if (
    unwrapped.kind === ts.SyntaxKind.NullKeyword ||
    (ts.isIdentifier(unwrapped) && unwrapped.text === "undefined")
  ) {
    return { static: true, value: null };
  }

  const value = staticStringValue(unwrapped);
  return value === null ? { static: false } : { static: true, value };
}

function prefixedRoutePath(prefix: string, path: string) {
  return [prefix, path]
    .flatMap((segment) => segment.split("/"))
    .filter(Boolean)
    .join("/");
}

function unwrapCallExpression(expression: ts.Expression) {
  const unwrapped = unwrapExpression(expression);
  return ts.isCallExpression(unwrapped) ? unwrapped : null;
}

function unwrapExpression(expression: ts.Expression): ts.Expression {
  if (
    ts.isParenthesizedExpression(expression) ||
    ts.isAsExpression(expression) ||
    ts.isSatisfiesExpression(expression)
  ) {
    return unwrapExpression(expression.expression);
  }

  return expression;
}

function unwrapRouteConfigExpression(expression: ts.Expression): ts.ArrayLiteralExpression | null {
  const unwrapped = unwrapExpression(expression);
  return ts.isArrayLiteralExpression(unwrapped) ? unwrapped : null;
}

function routeModuleIdentity(target: string) {
  let identity = posix.normalize(target.replaceAll("\\", "/")).replace(/^\.\//, "");
  identity = identity.replace(/\.[cm]?[jt]sx?$/i, "");
  if (identity.endsWith("/index")) identity = identity.slice(0, -"/index".length);

  return identity;
}

export function bareModuleSpecifierOffenders(
  specifiers: Iterable<string>,
  allowedSpecifiers: ReadonlySet<string>,
) {
  return [...specifiers]
    .filter((specifier) => !specifier.startsWith(".") && !allowedSpecifiers.has(specifier))
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

    for (const specifier of analyzeTypeScript(source, file).moduleSpecifiers) {
      if (specifier === "<non-static dynamic import>") {
        throw new Error(`Non-static dynamic import in ${file}`);
      }
      if (!specifier.startsWith(".")) continue;

      const dependency = resolveSourceFile(resolve(dirname(file), specifier));
      if (!dependency) {
        throw new Error(`Unable to resolve relative dependency "${specifier}" from ${file}`);
      }
      if (!visited.has(dependency)) pending.push(dependency);
    }
  }

  return [...visited];
}

export function emittedClassNames(
  source: string,
  filename: string,
  { unresolvedSpreads = "reject" }: { unresolvedSpreads?: "reject" | "skip" } = {},
) {
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

  const collectSpread = (expression: ts.Expression) => {
    if (ts.isParenthesizedExpression(expression)) {
      collectSpread(expression.expression);
      return;
    }

    if (ts.isConditionalExpression(expression)) {
      collectSpread(expression.whenTrue);
      collectSpread(expression.whenFalse);
      return;
    }

    if (!ts.isObjectLiteralExpression(expression)) {
      if (unresolvedSpreads === "skip") return;
      throw new Error(`Unsupported JSX spread: ${expression.getText(sourceFile)}`);
    }

    for (const property of expression.properties) {
      if (ts.isSpreadAssignment(property)) {
        collectSpread(property.expression);
        continue;
      }

      const propertyName = staticPropertyName(property.name);
      if (propertyName === null) {
        throw new Error(`Unsupported JSX spread property: ${property.getText(sourceFile)}`);
      }
      if (propertyName !== "className" && !propertyName.endsWith("ClassName")) continue;

      if (ts.isPropertyAssignment(property)) {
        collectExpression(property.initializer);
        continue;
      }

      throw new Error(`Unsupported JSX spread class property: ${property.getText(sourceFile)}`);
    }
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

    if (ts.isJsxSpreadAttribute(node)) collectSpread(node.expression);
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
  const sourceExtension = /\.[cm]?[jt]sx?$/i;
  for (const candidate of [
    path,
    `${path}.ts`,
    `${path}.tsx`,
    join(path, "index.ts"),
    join(path, "index.tsx"),
  ]) {
    if (sourceExtension.test(candidate) && existsSync(candidate) && statSync(candidate).isFile()) {
      return candidate;
    }
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

function staticPropertyName(name: ts.PropertyName | undefined) {
  if (!name) return null;
  if (ts.isIdentifier(name) || ts.isStringLiteralLike(name) || ts.isNumericLiteral(name)) {
    return name.text;
  }
  if (ts.isComputedPropertyName(name)) return staticStringValue(name.expression);

  return null;
}

function walk(node: ts.Node, visit: (node: ts.Node) => void) {
  visit(node);
  ts.forEachChild(node, (child) => walk(child, visit));
}
