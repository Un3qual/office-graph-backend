import type { ReactNode } from "react";
import { RelayEnvironmentProvider } from "react-relay";
import { getRelayEnvironment, type RelayEnvironment } from "./relay/environment";

type AppProvidersProps = {
  children: ReactNode;
  relayEnvironment?: RelayEnvironment;
};

export function AppProviders({ children, relayEnvironment }: AppProvidersProps) {
  return (
    <RelayEnvironmentProvider environment={relayEnvironment ?? getRelayEnvironment()}>
      {children}
    </RelayEnvironmentProvider>
  );
}
