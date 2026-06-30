import type { ReactNode } from "react";

type Props = {
  children?: ReactNode;
  title: string;
  tone?: "neutral" | "error";
};

export function EmptyState({ children, title, tone = "neutral" }: Props) {
  return (
    <div className="ui-empty-state" data-tone={tone}>
      <p className="ui-empty-title">{title}</p>
      {children ? <p>{children}</p> : null}
    </div>
  );
}
