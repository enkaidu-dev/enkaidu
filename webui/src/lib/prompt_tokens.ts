// Pure helpers for the Promptbar's macro and path-token manipulation.
//
// Kept free of the DOM/Svelte runtime so caret, token, and filter logic can be
// exercised by Vitest without mounting the Promptbar. The component keeps only
// the textarea measurement and overlay wiring and delegates to these helpers.

export type PromptMacro = {
  name: string;
  description: string;
  category: string;
};

export function macro_filter_text(input_text: string): string {
  if (!input_text.startsWith("!")) return "";
  const rest = input_text.slice(1);
  const ws = rest.search(/[ \t\n]/);
  return ws === -1 ? rest : rest.slice(0, ws);
}

// Index just past the `!name` token (i.e. the index of the first whitespace
// after the name, or the end of the input when there is none).
export function macro_name_end(input_text: string): number {
  if (!input_text.startsWith("!")) return 0;
  const rest = input_text.slice(1);
  const ws = rest.search(/[ \t\n]/);
  return ws === -1 ? input_text.length : 1 + ws;
}

export type MacroPickerState = {
  open: boolean;
  dismissed: boolean;
};

// Pure state transition for the short-lived macro picker dismissal flag and
// the open/close decision derived from the caret position. When the input is
// not macro-prefixed (or there are no macros) the dismissal is cleared so
// a later macro prefix starts fresh.
export function macro_picker_state(
  input_text: string,
  macros_length: number,
  macro_dismissed: boolean,
  caret: number,
): MacroPickerState {
  if (!input_text.startsWith("!") || macros_length === 0) {
    return { open: false, dismissed: false };
  }
  if (macro_dismissed) {
    return { open: false, dismissed: macro_dismissed };
  }
  const name_end = macro_name_end(input_text);
  return { open: caret <= name_end, dismissed: false };
}

export function is_path_token_char(code: number): boolean {
  return (
    (code >= 48 && code <= 57) || // 0-9
    (code >= 65 && code <= 90) || // A-Z
    (code >= 97 && code <= 122) || // a-z
    code === 46 || // .
    code === 95 || // _
    code === 45 || // -
    code === 47 // /
  );
}

export function path_token_at_caret(
  value: string,
  caret: number,
): { start: number; end: number; token: string } {
  let start = caret;
  while (start > 0 && is_path_token_char(value.charCodeAt(start - 1))) start--;
  let end = caret;
  while (end < value.length && is_path_token_char(value.charCodeAt(end))) end++;
  return { start, end, token: value.slice(start, end) };
}

export function is_path_like(token: string): boolean {
  return (
    token.includes("/") || token.startsWith("./") || token.startsWith("/")
  );
}

export function filter_macros(
  macros: PromptMacro[],
  filter: string,
  open: boolean,
  limit: number = 20,
): PromptMacro[] {
  if (!open || macros.length === 0) return [];
  const q = filter.trim().toLowerCase();
  if (!q) return macros.slice(0, limit);
  return macros
    .filter(
      (m) =>
        m.name.toLowerCase().includes(q) ||
        m.description.toLowerCase().includes(q) ||
        m.category.toLowerCase().includes(q),
    )
    .slice(0, limit);
}