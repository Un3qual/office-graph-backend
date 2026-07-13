import { Button as AriaButton, type ButtonProps, composeRenderProps } from "react-aria-components";

type Props = ButtonProps & {
  variant?: "primary" | "secondary";
};

export function Button({ className, variant = "secondary", ...props }: Props) {
  return (
    <AriaButton
      {...props}
      className={composeRenderProps(className, (className) =>
        [
          "ui-button",
          variant === "primary" ? "ui-button-primary" : "ui-button-secondary",
          className,
        ]
          .filter(Boolean)
          .join(" "),
      )}
    />
  );
}
