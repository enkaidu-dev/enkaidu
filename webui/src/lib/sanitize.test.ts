import { describe, expect, it } from "vitest";

import { sanitizeSvg } from "./sanitize";

describe("sanitizeSvg", () => {
  it("preserves a safe SVG element", () => {
    const result = sanitizeSvg('<svg><circle cx="5" cy="5" r="4" /></svg>');

    expect(result).toContain("<svg");
    expect(result).toContain("<circle");
    expect(result).not.toContain("<script");
  });

  it("strips script tags", () => {
    const result = sanitizeSvg(
      '<svg><script>alert("xss")</script><circle cx="5" cy="5" r="4" /></svg>',
    );

    expect(result).not.toContain("<script");
    expect(result).not.toContain("alert");
  });

  it("strips inline event handlers", () => {
    const result = sanitizeSvg(
      '<svg><circle cx="5" cy="5" r="4" onerror="alert(1)" onclick="evil()" /></svg>',
    );

    expect(result).not.toMatch(/onerror/i);
    expect(result).not.toMatch(/onclick/i);
    expect(result).toContain("<circle");
  });

  it("strips javascript: URIs", () => {
    const result = sanitizeSvg(
      '<svg><a href="javascript:alert(1)"><circle cx="5" cy="5" r="4" /></a></svg>',
    );

    expect(result).not.toMatch(/javascript:/i);
  });

  it("strips foreignObject (DOMPurify default would allow it)", () => {
    const result = sanitizeSvg(
      '<svg><foreignObject><img src="x" onerror="alert(1)" /></foreignObject></svg>',
    );

    expect(result).not.toMatch(/foreignObject/i);
    expect(result).not.toMatch(/onerror/i);
  });

  it("strips foreign HTML carrier elements", () => {
    const result = sanitizeSvg(
      '<svg><iframe src="x"></iframe><embed /><object data="x"></object></svg>',
    );

    expect(result).not.toMatch(/<iframe/i);
    expect(result).not.toMatch(/<embed/i);
    expect(result).not.toMatch(/<object/i);
  });
});