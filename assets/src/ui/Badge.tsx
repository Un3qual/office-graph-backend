import type { ReactNode } from "react";

export type BadgeTone = "teal" | "green" | "amber" | "blue" | "red" | "neutral";

type Props = {
  children: ReactNode;
  tone?: BadgeTone;
};

export function Badge({ children, tone = "neutral" }: Props) {
  return (
    <span className="ui-badge" data-tone={tone}>
      {children}
    </span>
  );
}
