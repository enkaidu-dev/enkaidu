import { describe, expect, it } from "vitest";

import {
  filter_macros,
  is_path_like,
  is_path_token_char,
  macro_filter_text,
  macro_name_end,
  macro_picker_state,
  path_token_at_caret,
  type PromptMacro,
} from "./prompt_tokens";

describe("prompt token helpers", () => {
  it("extracts the macro name up to the first whitespace", () => {
    expect(macro_filter_text("!foo arg")).toBe("foo");
    expect(macro_filter_text("!foo")).toBe("foo");
    expect(macro_filter_text("! foo")).toBe("");
    expect(macro_filter_text("plain text")).toBe("");
    expect(macro_filter_text("!a\tb\nc")).toBe("a");
  });

  it("computes the end of the macro name token", () => {
    expect(macro_name_end("!foo bar")).toBe(4);
    expect(macro_name_end("!foo")).toBe(4);
    expect(macro_name_end("!")).toBe(1);
    expect(macro_name_end("foo")).toBe(0);
  });

  it("clears the dismissal for non-macro input", () => {
    expect(
      macro_picker_state("hello", 3, true, 0),
    ).toEqual({ open: false, dismissed: false });
    expect(macro_picker_state("", 0, true, 0)).toEqual({
      open: false,
      dismissed: false,
    });
  });

  it("keeps a dismissed macro picker closed", () => {
    expect(macro_picker_state("!foo", 3, true, 0)).toEqual({
      open: false,
      dismissed: true,
    });
  });

  it("opens the macro picker while the caret is within the name", () => {
    expect(macro_picker_state("!foo bar", 3, false, 2)).toEqual({
      open: true,
      dismissed: false,
    });
    expect(macro_picker_state("!foo bar", 3, false, 4)).toEqual({
      open: true,
      dismissed: false,
    });
  });

  it("closes the macro picker once the caret moves into arguments", () => {
    expect(macro_picker_state("!foo bar", 3, false, 5)).toEqual({
      open: false,
      dismissed: false,
    });
  });

  it("recognises path-token characters", () => {
    expect(is_path_token_char(48)).toBe(true); // 0
    expect(is_path_token_char(65)).toBe(true); // A
    expect(is_path_token_char(97)).toBe(true); // a
    expect(is_path_token_char(46)).toBe(true); // .
    expect(is_path_token_char(47)).toBe(true); // /
    expect(is_path_token_char(32)).toBe(false); // space
    expect(is_path_token_char(33)).toBe(false); // !
  });

  it("scans the path token in both directions from the caret", () => {
    const value = "see ./src/foo.txt now";
    const caret = value.indexOf("foo") + 1;
    const result = path_token_at_caret(value, caret);
    expect(result).toEqual({
      start: value.indexOf("./"),
      end: value.indexOf(" now"),
      token: "./src/foo.txt",
    });
  });

  it("captures an empty token at a non-path caret", () => {
    expect(path_token_at_caret("! hello", 1)).toEqual({
      start: 1,
      end: 1,
      token: "",
    });
  });

  it("identifies path-like tokens", () => {
    expect(is_path_like("./src")).toBe(true);
    expect(is_path_like("/usr/bin")).toBe(true);
    expect(is_path_like("a/b")).toBe(true);
    expect(is_path_like("filename")).toBe(false);
    expect(is_path_like("plain")).toBe(false);
  });

  it("filters macros case-insensitively and limits the list", () => {
    const macros: PromptMacro[] = [
      { name: "Help", description: "show", category: "info" },
      { name: "History", description: "past", category: "nav" },
      { name: "Other", description: "helpful", category: "misc" },
    ];
    expect(filter_macros(macros, "", false, 20)).toEqual([]);
    expect(filter_macros(macros, "", true, 2)).toEqual(macros.slice(0, 2));
    expect(
      filter_macros(macros, "HELP", true, 20).map((m) => m.name),
    ).toEqual(["Help", "Other"]);
  });
});