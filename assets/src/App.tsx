import "./styles/global.css";
import { AppProviders } from "../app/AppProviders";
import type { RelayEnvironment } from "../app/relay/environment";
import OperatorRoute from "../app/routes/operator/route";

type Props = {
  relayEnvironment?: RelayEnvironment;
};

export function App({ relayEnvironment }: Props) {
  return (
    <AppProviders relayEnvironment={relayEnvironment}>
      <OperatorRoute />
    </AppProviders>
  );
}
