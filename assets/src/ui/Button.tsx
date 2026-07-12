import { Button as AriaButton, composeRenderProps, type ButtonProps } from "react-aria-components";

type Props = ButtonProps & {
  variant?: "primary" | "secondary";
};

export function Button({ className, variant = "secondary", ...props }: Props) {
  return (
    <AriaButton
      {...props}
      className={composeRenderProps(className, (className) =>
        ["ui-button", `ui-button-${variant}`, className].filter(Boolean).join(" "),
      )}
    />
  );
}
