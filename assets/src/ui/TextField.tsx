import {
  Input,
  Label,
  TextField as AriaTextField,
  type TextFieldProps
} from "react-aria-components";

type Props = Omit<TextFieldProps, "children"> & {
  label: string;
  placeholder?: string;
};

export function TextField({ label, placeholder, ...props }: Props) {
  return (
    <AriaTextField {...props} className="ui-text-field">
      <Label>{label}</Label>
      <Input placeholder={placeholder} />
    </AriaTextField>
  );
}
