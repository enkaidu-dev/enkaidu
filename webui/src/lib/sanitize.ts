import DOMPurify from "dompurify";

// Sanitize raw SVG source so that it is safe to insert via {@html}.
//
// DOMPurify's `svg` profile allows SVG markup and SVG-scoped attributes
// but still strips `<script>`, `on*` event handlers, and `javascript:`/
// `data:` URIs by default. We explicitly add `foreignObject` to the
// forbidden list — it can contain an arbitrary HTML fragment (including
// event-handler attributes) that escapes the SVG sandbox, and DOMPurify's
// default svg profile does NOT block it.
//
// Also forbidden: `iframe`, `embed`, and `object` — these are not
// valid SVG elements and are the classic XSS carriers that can slip
// through if DOMPurify's tag list is not strict.
const SVG_FORBID_TAGS = [
  "foreignObject",
  "script",
  "iframe",
  "embed",
  "object",
] as const;

export function sanitizeSvg(source: string): string {
  return DOMPurify.sanitize(source, {
    USE_PROFILES: { svg: true },
    FORBID_TAGS: [...SVG_FORBID_TAGS],
   });
}
