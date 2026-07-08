import {
  Environment,
  Network,
  RecordSource,
  Store,
  type FetchFunction
} from "relay-runtime";
import { fetchGraphQL } from "./fetchGraphQL";

export type RelayEnvironment = Environment;

let browserRelayEnvironment: Environment | null = null;

const RELAY_GC_RELEASE_BUFFER_SIZE = 5;
const globalIDTypes = new Set([
  "OperatorWorkflowItem",
  "Signal",
  "WorkPacket",
  "WorkRun"
]);

export function createRelayEnvironment() {
  const fetchRelay: FetchFunction = (request, variables) => fetchGraphQL(request, variables);

  return new Environment({
    getDataID: getOfficeGraphDataID,
    network: Network.create(fetchRelay),
    store: new Store(new RecordSource(), {
      gcReleaseBufferSize: RELAY_GC_RELEASE_BUFFER_SIZE
    })
  });
}

export function getRelayEnvironment() {
  browserRelayEnvironment ??= createRelayEnvironment();
  return browserRelayEnvironment;
}

export function getOfficeGraphDataID(
  fieldValue: Record<string, unknown>,
  typeName: string
): string | null {
  if (globalIDTypes.has(typeName) && typeof fieldValue.id === "string") {
    return fieldValue.id;
  }

  return null;
}
