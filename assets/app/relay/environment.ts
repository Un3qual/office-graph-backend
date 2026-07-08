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

export function createRelayEnvironment() {
  const fetchRelay: FetchFunction = (request, variables) => fetchGraphQL(request, variables);

  return new Environment({
    network: Network.create(fetchRelay),
    store: new Store(new RecordSource())
  });
}

export function getRelayEnvironment() {
  browserRelayEnvironment ??= createRelayEnvironment();
  return browserRelayEnvironment;
}
