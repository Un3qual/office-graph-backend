import { formatWorkflowStatus, statusTone } from "../operator-workflow/status";

type Props = {
  status: string;
};

export function StatusBadge({ status }: Props) {
  return (
    <span className="status-badge" data-tone={statusTone(status)}>
      {formatWorkflowStatus(status)}
    </span>
  );
}
