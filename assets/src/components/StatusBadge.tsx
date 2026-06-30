import { Badge } from "../ui/Badge";
import { formatWorkflowStatus, statusTone } from "../operator-workflow/status";

type Props = {
  status: string;
};

export function StatusBadge({ status }: Props) {
  return <Badge tone={statusTone(status)}>{formatWorkflowStatus(status)}</Badge>;
}
