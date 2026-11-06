import { describe, expect, it } from "vitest";

import { mimeForExt, serializeSvg } from "./save";

describe("mimeForExt", () => {
  it("maps common extensions to MIME types", () => {
    expect(mimeForExt("svg")).toBe("image/svg+xml;charset=utf-8");
    expect(mimeForExt("SVG")).toBe("image/svg+xml;charset=utf-8");
    expect(mimeForExt("json")).toBe("application/json;charset=utf-8");
    expect(mimeForExt("csv")).toBe("text/csv;charset=utf-8");
    expect(mimeForExt("md")).toBe("text/markdown;charset=utf-8");
    expect(mimeForExt("markdown")).toBe("text/markdown;charset=utf-8");
    expect(mimeForExt("xml")).toBe("application/xml;charset=utf-8");
    expect(mimeForExt("drawio")).toBe("application/xml;charset=utf-8");
    expect(mimeForExt("png")).toBe("image/png");
  });

  it("falls back to text/plain for unknown extensions", () => {
    expect(mimeForExt("")).toBe("text/plain;charset=utf-8");
    expect(mimeForExt("txt")).toBe("text/plain;charset=utf-8");
    expect(mimeForExt("weird")).toBe("text/plain;charset=utf-8");
  });
});

describe("serializeSvg", () => {
  it("returns null for a null input", () => {
    expect(serializeSvg(null)).toBeNull();
  });

  it("injects the svg namespace and XML declaration", () => {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    const circle = document.createElementNS(
      "http://www.w3.org/2000/svg",
      "circle",
    );
    circle.setAttribute("cx", "5");
    svg.appendChild(circle);

    const result = serializeSvg(svg);

    expect(result).not.toBeNull();
    expect(result).toMatch(/^<\?xml version="1.0" encoding="utf-8"\?>/);
    expect(result).toContain('xmlns="http://www.w3.org/2000/svg"');
    expect(result).toContain("<circle");
  });
});