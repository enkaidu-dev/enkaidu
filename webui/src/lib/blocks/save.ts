// Shared "save to file" support for the rendered-block system.
//
// A block renderer (registry entry) advertises one or more SaveOption chips;
// BlockFrame renders a chip per option that is currently *available*, and on
// click runs the option's produce() to get the bytes and downloads them as
// <saveBasename>.<ext>. This keeps the *what can be saved* decision in the
// renderer (e.g. mermaid offers Source + rendered-SVG, vega offers JSON +
// rendered-SVG, markdown offers Source) instead of BlockFrame having to sniff
// the content for a particular shape (as the old hasSvg-based "Save SVG" did).

export interface SaveContext {
  source: string;
  language: string;
   // The BlockFrame root element, so a producer can read the live rendered
  // <svg> (or any other rendered node) from the diagram view.
  frame: HTMLElement;
}

export interface SaveOption {
  label: string;
  ext: string;
   // Optional content type; defaults to mimeForExt(ext) when omitted.
  mime?: string;
   // When this option is currently available to offer. Omitted => always
  // available (used by source-based saves that need no rendered DOM).
  available?(ctx: SaveContext): boolean;
   // Compute the bytes to download, on click. Returns a string (any text)
  // or a Blob. A source-based save just echoes ctx.source.
  produce(ctx: SaveContext): string | Blob;
}

// Map a file extension to a content type for the Blob.
export function mimeForExt(ext: string): string {
  switch (ext.toLowerCase()) {
    case "svg":
      return "image/svg+xml;charset=utf-8";
    case "json":
      return "application/json;charset=utf-8";
    case "csv":
      return "text/csv;charset=utf-8";
    case "md":
    case "markdown":
      return "text/markdown;charset=utf-8";
    case "png":
      return "image/png";
    default:
      return "text/plain;charset=utf-8";
   }
}

// Serialize a rendered <svg> element to a standalone .svg file string,
// injecting the XML namespaces + an XML header when the emitting renderer
// (mermaid / vega / inline svg) omitted them. Lifted from BlockFrame and
// shared by every rendered-SVG save option.
export function serializeSvg(svg: SVGElement | null): string | null {
  if (!svg) return null;
  const serializer = new XMLSerializer();
  let result = serializer.serializeToString(svg);
  if (!/^<svg[^>]+xmlns="http:\/\/www\.w3\.org\/2000\/svg"/.test(result)) {
    result = result.replace(/^<svg/, '<svg xmlns="http://www.w3.org/2000/svg"');
   }
  if (!/^<svg[^>]+xmlns:xlink="http:\/\/www\.w3\.org\/1999\/xlink"/.test(result)) {
    result = result.replace(/^<svg/, '<svg xmlns:xlink="http://www.w3.org/1999/xlink"');
   }
  return '<?xml version="1.0" encoding="utf-8"?>\n' + result;
}

// Trigger a browser download of `content` under `name` with the given mime.
export function download(name: string, content: string | Blob, mime?: string): void {
  const blob =
    content instanceof Blob
     ? content
     : new Blob([content], { type: mime ?? "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// --- convenience factories so registry entries stay one-liners ---

// A source-based save: the raw fence text, saved verbatim. Always available
// (needs no rendered DOM).
export function saveSource(label: string, ext: string): SaveOption {
  return {
    label,
    ext,
    produce: (ctx) => ctx.source,
   };
}

// A rendered-SVG save: the live <svg> in the frame body, serialized to a
// standalone file. Only offered in the diagram view (where the <svg> exists);
// if it has since vanished, produce returns "" and BlockFrame skips the empty
// download.
export function saveRenderedSvg(label = "SVG", ext = "svg"): SaveOption {
  return {
    label,
    ext,
    available: (ctx) => ctx.frame.querySelector("svg") !== null,
    produce: (ctx) => {
      const serialized = serializeSvg(ctx.frame.querySelector("svg") ?? null);
      return serialized ?? "";
     },
   };
}
