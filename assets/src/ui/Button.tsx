import { Button as AriaButton, type ButtonProps } from "react-aria-components";

type Props = ButtonProps & {
  variant?: "primary" | "secondary";
};

export function Button({ className, variant = "secondary", ...props }: Props) {
  return (
    <AriaButton
      {...props}
      className={["ui-button", `ui-button-${variant}`, className].filter(Boolean).join(" ")}
    />
  );
}
