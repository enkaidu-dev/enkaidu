
export type SecurityBanner = {
  safe: boolean;
  message: string;
};

// Base config for the single unified security dialog. It carries every
// field both former dialog variants needed; `rememberable` only affects
// whether the "Remember" checkbox is offered.
export type SecurityDialogConfig = {
  description: string;
  subjects: string[];
  banner: SecurityBanner | null;
  id: string;
  show: boolean;
  rememberable?: boolean;
}

// Backwards-compatible aliases for the now-merged dialog types.
export type SecurityConfirmDialogConfig = SecurityDialogConfig;
export type SecurityPermissionDialogConfig = SecurityDialogConfig;



// The unified dialog always offers the third argument; confirm-style
// callers simply ignore it.
export type SecurityDialogSubmit = (
  id: string,
  approved: boolean,
  remember?: boolean,
) => void
export type SecurityConfirmSubmit = SecurityDialogSubmit;
export type SecurityPermissionSubmit = SecurityDialogSubmit;

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
  pre_filled?: InputValues | null;
}
