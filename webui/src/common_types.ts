
export type SecurityConfirmDialogConfig = {
  description: string;
  subject: string;
  id: string;
  show: boolean;
}

export type SecurityConfirmSubmit = (id: string, approved: boolean) => void

// for InputDialog
export type InputArg = {
  type: string;
  name: string;
  description?: string | undefined;
};

export type InputValues = { [name: string]: string }

export type InputSubmit = (id: string, inputs: InputValues) => void

export type InputDialogConfig = {
  show: boolean;
  id: string;
  title: string;
  description?: string | undefined;
  input_arguments: InputArg[];
}
