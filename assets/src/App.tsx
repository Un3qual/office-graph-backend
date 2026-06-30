import "./styles/global.css";
import { OperatorConsole } from "./operator-workflow/OperatorConsole";
import type { OperatorWorkflowApi } from "./operator-workflow/api";

type Props = {
  api?: OperatorWorkflowApi;
};

export function App({ api }: Props) {
  return <OperatorConsole api={api} />;
}
