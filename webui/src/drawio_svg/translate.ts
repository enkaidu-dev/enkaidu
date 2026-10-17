/**
 * Draw.io (mxGraph) XML → SVG for generated diagrams.
 *
 * Renders a documented subset of draw.io and reports everything outside that
 * subset as diagnostics instead of guessing silently. Pure TypeScript with no
 * dependencies, no DOM and no Node built-ins. The output is plain SVG: no
 * scripts, no foreignObject, no external references.
 *
 * ```ts
 * if (sniffDrawio(text) === 'complete') {
 *   const result = renderDrawio(text)
 *   if (result.ok) for (const page of result.pages) show(page.svg, page.fidelity, page.diagnostics)
 *   else showSource(text, result.error)
 * }
 * ```
 *
 * Derived from the dsh-drawio translate module.
 *
 * @module drawio-svg
 */

/* ================================================================== *
 * Public API
 * ================================================================== */

/**
 * `unsupported`: the element was replaced by a placeholder or omitted.
 * `approximated`: the element was drawn, but not exactly as draw.io draws it.
 */
export type Severity = 'unsupported' | 'approximated'

/** Something in the input that the renderer did not draw exactly as draw.io would. */
export interface Diagnostic {
  severity: Severity
  /** The cell concerned, or null for page-level issues. */
  cellId: string | null
  /** Stable feature key, e.g. `shape=mxgraph.aws4.lambda`, `style:shadow`, `html:<table>`, `css:line-height`. */
  feature: string
  /** Human-readable explanation. */
  message: string
}

/**
 * `full`: rendered with no diagnostics. `partial`: rendered, with diagnostics.
 * `none`: the page contains nothing renderable.
 */
export type Fidelity = 'full' | 'partial' | 'none'

/** One rendered page (`<diagram>`) of a draw.io document. */
export interface RenderedPage {
  name: string
  id: string
  /** Standalone SVG document with width, height and viewBox set. */
  svg: string
  width: number
  height: number
  fidelity: Fidelity
  diagnostics: Diagnostic[]
}

/** Outcome of {@link renderDrawio}: pages on success, or the reason nothing could be rendered. */
export type RenderResult = { ok: true; pages: RenderedPage[] } | { ok: false; error: string }

/** Rendering options; every field is optional. */
export interface RenderOptions {
  /** Fallback CSS font-family list appended to each label's font. Default `Helvetica, Arial, sans-serif`. */
  fontFamily?: string
  /** Margin around the drawing in px. Default 10. */
  padding?: number
  /** Paint the page background colour declared by the model. Default true. */
  background?: boolean
  /** Prefix for gradient ids; make it unique per SVG when several are inlined in one document. Default `dio`. */
  idPrefix?: string
  /**
   * Raw-deflate decompressor for compressed pages, e.g. Node's `zlib.inflateRawSync`.
   * Without it, a compressed page makes the whole render fail with an explanatory error.
   */
  inflateRaw?: (data: Uint8Array) => Uint8Array
}

/**
 * `none`: not draw.io XML. `incomplete`: a draw.io root has opened but not yet
 * closed (e.g. while streaming). `complete`: the root's closing tag ends the text.
 */
export type SniffResult = 'none' | 'incomplete' | 'complete'

/**
 * Classify text as draw.io XML: an `<mxfile>` or `<mxGraphModel>` root,
 * optionally preceded by an XML prolog and comments.
 */
export function sniffDrawio(text: string): SniffResult {
  const head = /^\uFEFF?\s*(?:<\?xml[^>]*\?>\s*)?(?:<!--[\s\S]*?-->\s*)*<(mxfile|mxGraphModel)(?=[\s>/])/.exec(text)
  if (head === null) return 'none'
  return text.trimEnd().endsWith(`</${head[1] ?? ''}>`) ? 'complete' : 'incomplete'
}

/**
 * Render every page of a draw.io document to SVG.
 *
 * Accepts a full `<mxfile>` (one page per `<diagram>`) or a bare
 * `<mxGraphModel>`. Never throws: malformed XML, a root that is not draw.io,
 * or a compressed page without `options.inflateRaw` yields `{ ok: false, error }`.
 */
export function renderDrawio(xml: string, options: RenderOptions = {}): RenderResult {
  try {
    const pages = loadPages(xml, options.inflateRaw)
    return { ok: true, pages: pages.map((page, index) => renderPage(page, options, index)) }
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) }
  }
}

/** Shape names the renderer draws. Anything else becomes a dashed placeholder. */
export const SUPPORTED_SHAPES: readonly string[] = [
  'rectangle', 'ellipse', 'doubleEllipse', 'rhombus', 'hexagon', 'triangle', 'parallelogram',
  'trapezoid', 'cylinder', 'cylinder3', 'process', 'document', 'swimlane', 'line',
]

/** Arrowhead names the renderer draws for `startArrow` / `endArrow`. */
export const SUPPORTED_ARROWS: readonly string[] = [
  'none', 'classic', 'classicThin', 'block', 'blockThin', 'open', 'openThin', 'oval', 'diamond',
  'diamondThin', 'ERone', 'ERmandOne', 'ERmany', 'ERoneToMany', 'ERzeroToOne', 'ERzeroToMany',
]

/** Values of `edgeStyle` the renderer routes. */
export const SUPPORTED_EDGE_STYLES: readonly string[] = [
  'none', 'orthogonalEdgeStyle', 'elbowEdgeStyle', 'entityRelationEdgeStyle',
]

/** HTML tags honoured in `html=1` labels. Other tags are dropped (their text is kept). */
export const SUPPORTED_HTML_TAGS: readonly string[] = [
  'b', 'strong', 'i', 'em', 'u', 'ins', 's', 'strike', 'del', 'font', 'span', 'a', 'code', 'tt',
  'br', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
]

/** CSS properties honoured in `style` attributes inside HTML labels. */
export const SUPPORTED_CSS_PROPERTIES: readonly string[] = [
  'color', 'font-size', 'font-weight', 'font-style', 'font-family', 'text-decoration',
  'text-decoration-line', 'text-align',
]

/* ================================================================== *
 * Geometry primitives
 * ================================================================== */

interface Pt { x: number; y: number }
interface Box { x: number; y: number; w: number; h: number }
/** Affine matrix [a b c d e f]: x' = a·x + c·y + e, y' = b·x + d·y + f. */
type Mat = [number, number, number, number, number, number]

const IDENTITY: Mat = [1, 0, 0, 1, 0, 0]

function mul(m: Mat, n: Mat): Mat {
  return [
    m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1],
    m[0] * n[2] + m[2] * n[3], m[1] * n[2] + m[3] * n[3],
    m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5],
  ]
}

function rotateAbout(deg: number, c: Pt): Mat {
  if (deg % 360 === 0) return IDENTITY
  const rad = (deg * Math.PI) / 180
  const cos = Math.cos(rad)
  const sin = Math.sin(rad)
  return [cos, sin, -sin, cos, c.x - cos * c.x + sin * c.y, c.y - sin * c.x - cos * c.y]
}

function scaleAbout(sx: number, sy: number, c: Pt): Mat {
  return [sx, 0, 0, sy, c.x - sx * c.x, c.y - sy * c.y]
}

function apply(m: Mat, p: Pt): Pt {
  return { x: m[0] * p.x + m[2] * p.y + m[4], y: m[1] * p.x + m[3] * p.y + m[5] }
}

function applyLinear(m: Mat, p: Pt): Pt {
  return { x: m[0] * p.x + m[2] * p.y, y: m[1] * p.x + m[3] * p.y }
}

const isIdentity = (m: Mat): boolean => m.every((v, i) => Math.abs(v - (IDENTITY[i] ?? 0)) < 1e-9)

const center = (b: Box): Pt => ({ x: b.x + b.w / 2, y: b.y + b.h / 2 })

const corners = (b: Box): Pt[] => [
  { x: b.x, y: b.y }, { x: b.x + b.w, y: b.y }, { x: b.x + b.w, y: b.y + b.h }, { x: b.x, y: b.y + b.h },
]

function aabb(points: Pt[]): Box {
  let minX = Infinity
  let minY = Infinity
  let maxX = -Infinity
  let maxY = -Infinity
  for (const p of points) {
    minX = Math.min(minX, p.x)
    minY = Math.min(minY, p.y)
    maxX = Math.max(maxX, p.x)
    maxY = Math.max(maxY, p.y)
  }
  return { x: minX, y: minY, w: maxX - minX, h: maxY - minY }
}

const near = (a: number, b: number): boolean => Math.abs(a - b) < 0.5

class Bounds {
  minX = Infinity
  minY = Infinity
  maxX = -Infinity
  maxY = -Infinity

  add(p: Pt): void {
    if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) return
    this.minX = Math.min(this.minX, p.x)
    this.minY = Math.min(this.minY, p.y)
    this.maxX = Math.max(this.maxX, p.x)
    this.maxY = Math.max(this.maxY, p.y)
  }

  addBox(b: Box, m: Mat = IDENTITY): void {
    for (const p of corners(b)) this.add(apply(m, p))
  }

  get empty(): boolean {
    return !Number.isFinite(this.minX)
  }
}

/* ================================================================== *
 * Serialisation helpers
 * ================================================================== */

function fmt(n: number): string {
  if (!Number.isFinite(n)) return '0'
  const r = Math.round(n * 100) / 100
  return Object.is(r, -0) ? '0' : String(r)
}

const fmtPt = (p: Pt): string => `${fmt(p.x)} ${fmt(p.y)}`

function esc(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;')
}

const matAttr = (m: Mat): string => (isIdentity(m) ? '' : ` transform="matrix(${m.map(fmt).join(' ')})"`)

function num(value: string | undefined, fallback: number): number {
  if (value === undefined || value.trim() === '') return fallback
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

/* ================================================================== *
 * XML parsing
 * ================================================================== */

interface XmlNode {
  name: string
  attrs: Record<string, string>
  children: XmlNode[]
  /** Concatenated decoded text and CDATA content. */
  text: string
}

const XML_ENTITIES = new Map<string, string>([['amp', '&'], ['lt', '<'], ['gt', '>'], ['quot', '"'], ['apos', "'"]])

function decodeEntities(value: string, table: Map<string, string>): string {
  if (!value.includes('&')) return value
  return value.replace(/&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z][a-zA-Z0-9]*);/g, (match, body: string) => {
    if (body.startsWith('#')) {
      const hex = body[1] === 'x' || body[1] === 'X'
      const code = Number.parseInt(body.slice(hex ? 2 : 1), hex ? 16 : 10)
      return Number.isInteger(code) && code >= 0 && code <= 0x10ffff ? String.fromCodePoint(code) : match
    }
    return table.get(body) ?? match
  })
}

/**
 * Recursive-descent parser for well-formed XML: elements, attributes, text,
 * CDATA, comments, processing instructions and a DOCTYPE. Attribute values are
 * whitespace-normalised and entity-decoded as the XML specification requires.
 */
function parseXml(input: string): XmlNode {
  const src = input.replace(/^\uFEFF/, '')
  let pos = 0

  const fail = (message: string): never => {
    const line = src.slice(0, pos).split('\n').length
    throw new Error(`XML parse error at line ${line}: ${message}`)
  }
  const skipSpace = (): void => {
    while (pos < src.length && /\s/.test(src.charAt(pos))) pos += 1
  }
  const skipUntil = (terminator: string, what: string): void => {
    const end = src.indexOf(terminator, pos)
    if (end === -1) fail(`unterminated ${what}`)
    pos = end + terminator.length
  }
  const skipMisc = (): void => {
    for (; ;) {
      skipSpace()
      if (src.startsWith('<?', pos)) skipUntil('?>', 'processing instruction')
      else if (src.startsWith('<!--', pos)) skipUntil('-->', 'comment')
      else if (/^<!DOCTYPE/i.test(src.slice(pos, pos + 9))) {
        let depth = 0
        for (; ;) {
          const ch = src.charAt(pos)
          if (ch === '') fail('unterminated DOCTYPE')
          pos += 1
          if (ch === '<') depth += 1
          else if (ch === '>' && --depth === 0) break
        }
      } else return
    }
  }
  const readName = (): string => {
    const start = pos
    while (pos < src.length && /[A-Za-z0-9_:.\-]/.test(src.charAt(pos))) pos += 1
    if (pos === start) fail('expected a name')
    return src.slice(start, pos)
  }
  const readAttrs = (): Record<string, string> => {
    const attrs: Record<string, string> = Object.create(null) as Record<string, string>
    for (; ;) {
      skipSpace()
      const ch = src.charAt(pos)
      if (ch === '' || ch === '>' || ch === '/') return attrs
      const name = readName()
      skipSpace()
      if (src.charAt(pos) !== '=') fail(`attribute ${name} is missing '='`)
      pos += 1
      skipSpace()
      const quote = src.charAt(pos)
      if (quote !== '"' && quote !== "'") fail(`attribute ${name} is not quoted`)
      const end = src.indexOf(quote, pos + 1)
      if (end === -1) fail(`attribute ${name} is unterminated`)
      attrs[name] = decodeEntities(src.slice(pos + 1, end).replace(/[\t\n\r]/g, ' '), XML_ENTITIES)
      pos = end + 1
    }
  }
  const parseElement = (): XmlNode => {
    pos += 1
    const name = readName()
    const attrs = readAttrs()
    if (src.startsWith('/>', pos)) {
      pos += 2
      return { name, attrs, children: [], text: '' }
    }
    if (src.charAt(pos) !== '>') fail(`malformed start tag <${name}>`)
    pos += 1
    const children: XmlNode[] = []
    let text = ''
    for (; ;) {
      if (pos >= src.length) fail(`element <${name}> is not closed`)
      if (src.startsWith('</', pos)) {
        pos += 2
        const closing = readName()
        skipSpace()
        if (src.charAt(pos) !== '>') fail('malformed end tag')
        pos += 1
        if (closing !== name) fail(`</${closing}> does not close <${name}>`)
        return { name, attrs, children, text }
      }
      if (src.startsWith('<![CDATA[', pos)) {
        const end = src.indexOf(']]>', pos + 9)
        if (end === -1) fail('unterminated CDATA')
        text += src.slice(pos + 9, end)
        pos = end + 3
      } else if (src.startsWith('<!--', pos)) {
        skipUntil('-->', 'comment')
      } else if (src.startsWith('<?', pos)) {
        skipUntil('?>', 'processing instruction')
      } else if (src.charAt(pos) === '<') {
        children.push(parseElement())
      } else {
        const start = pos
        while (pos < src.length && src.charAt(pos) !== '<') pos += 1
        text += decodeEntities(src.slice(start, pos), XML_ENTITIES)
      }
    }
  }

  skipMisc()
  if (src.charAt(pos) !== '<') fail('expected a root element')
  const root = parseElement()
  skipMisc()
  if (pos < src.length) fail('unexpected content after the root element')
  return root
}

/* ================================================================== *
 * Pages and compression
 * ================================================================== */

interface PageSource { name: string; id: string; model: XmlNode }

function base64ToBytes(b64: string): Uint8Array {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  const clean = b64.replace(/[^A-Za-z0-9+/]/g, '')
  const out = new Uint8Array(Math.floor((clean.length * 3) / 4))
  let buffer = 0
  let bits = 0
  let n = 0
  for (const ch of clean) {
    buffer = ((buffer << 6) | alphabet.indexOf(ch)) & 0xffffff
    bits += 6
    if (bits >= 8) {
      bits -= 8
      out[n++] = (buffer >> bits) & 0xff
    }
  }
  return out.subarray(0, n)
}

/** draw.io compression: base64 → raw inflate → URI-decode. */
function inflatePage(payload: string, inflateRaw: (data: Uint8Array) => Uint8Array): string {
  const bytes = inflateRaw(base64ToBytes(payload))
  let text = ''
  for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return decodeURIComponent(text)
}

function loadPages(xml: string, inflateRaw: RenderOptions['inflateRaw']): PageSource[] {
  const root = parseXml(xml)
  if (root.name === 'mxGraphModel') return [{ name: 'Page-1', id: '', model: root }]
  if (root.name !== 'mxfile') {
    throw new Error(`not a draw.io document: expected <mxfile> or <mxGraphModel>, found <${root.name}>`)
  }
  const pages: PageSource[] = []
  for (const diagram of root.children) {
    if (diagram.name !== 'diagram') continue
    const name = diagram.attrs.name ?? `Page-${pages.length + 1}`
    let model = diagram.children.find(child => child.name === 'mxGraphModel')
    if (model === undefined) {
      const payload = diagram.text.trim()
      if (payload === '') continue
      if (inflateRaw === undefined) throw new Error(`page "${name}" is compressed; pass options.inflateRaw to render it`)
      model = parseXml(inflatePage(payload, inflateRaw))
      if (model.name !== 'mxGraphModel') throw new Error(`page "${name}" does not decompress to an <mxGraphModel>`)
    }
    pages.push({ name, id: diagram.attrs.id ?? '', model })
  }
  if (pages.length === 0) throw new Error('the <mxfile> contains no diagrams')
  return pages
}

/* ================================================================== *
 * Styles
 * ================================================================== */

type Style = Record<string, string>

const newStyle = (...sources: Style[]): Style => Object.assign(Object.create(null) as Style, ...sources)

const DEFAULT_VERTEX: Style = newStyle({
  shape: 'rectangle', fillColor: 'default', strokeColor: 'default', fontColor: 'default',
  fontSize: '12', fontFamily: 'Helvetica', align: 'center', verticalAlign: 'middle',
})

const DEFAULT_EDGE: Style = newStyle({
  shape: 'connector', endArrow: 'classic', strokeColor: 'default', fontColor: 'default',
  fontSize: '11', fontFamily: 'Helvetica', align: 'center', verticalAlign: 'middle', labelBackgroundColor: 'default',
})

const TEXT_STYLE: Style = { fillColor: 'none', strokeColor: 'none', align: 'left', verticalAlign: 'top' }

/** Named styles from draw.io's default stylesheet that the renderer honours. */
const NAMED_STYLES = new Map<string, Style>([
  ['text', TEXT_STYLE],
  ['edgeLabel', { ...TEXT_STYLE, labelBackgroundColor: 'default', fontSize: '11' }],
  ['ellipse', { shape: 'ellipse' }],
  ['rhombus', { shape: 'rhombus' }],
  ['triangle', { shape: 'triangle' }],
  ['swimlane', { shape: 'swimlane', fontStyle: '1', startSize: '23' }],
  ['group', { fillColor: 'none', strokeColor: 'none', verticalAlign: 'top' }],
  ['line', { shape: 'line', strokeWidth: '4', labelBackgroundColor: 'default', verticalAlign: 'top', spacingTop: '8' }],
  ['image', { shape: 'image' }],
])

const RENDERED_KEYS = new Set([
  'shape', 'rounded', 'arcSize', 'absoluteArcSize', 'fillColor', 'gradientColor', 'gradientDirection',
  'strokeColor', 'strokeWidth', 'dashed', 'dashPattern', 'fixDash', 'opacity', 'fillOpacity', 'strokeOpacity',
  'textOpacity', 'rotation', 'direction', 'flipH', 'flipV', 'size', 'fixedSize', 'margin', 'startSize',
  'horizontal', 'swimlaneFillColor', 'swimlaneLine', 'fontColor', 'fontSize', 'fontFamily', 'fontStyle',
  'align', 'verticalAlign', 'labelPosition', 'verticalLabelPosition', 'spacing', 'spacingTop', 'spacingBottom',
  'spacingLeft', 'spacingRight', 'labelBackgroundColor', 'labelBorderColor', 'whiteSpace', 'html', 'noLabel',
  'edgeStyle', 'elbow', 'curved', 'endArrow', 'startArrow', 'endSize', 'endFill', 'startFill', 'exitX',
  'exitY', 'exitDx', 'exitDy', 'exitPerimeter', 'entryX', 'entryY', 'entryDx', 'entryDy', 'entryPerimeter',
  'segment',
])

/** Keys that only affect editing behaviour or automatic layout, so a static rendering ignores them. */
const INERT_KEYS = new Set([
  'resizable', 'movable', 'rotatable', 'deletable', 'editable', 'cloneable', 'bendable', 'connectable',
  'locked', 'autosize', 'points', 'pointerEvents', 'perimeter', 'container', 'collapsible',
  'recursiveResize', 'expand', 'childLayout', 'resizeParent', 'resizeParentMax', 'resizeLast',
  'horizontalStack', 'stackLayout', 'marginTop', 'marginBottom', 'marginLeft', 'marginRight', 'stackFill',
  'stackSpacing', 'treeFolding', 'treeMoving', 'metaEdit', 'allowArrows', 'snapToPoint', 'part',
  'portConstraint', 'sourcePortConstraint', 'targetPortConstraint', 'portConstraintRotation', 'aspect',
  'backgroundOutline', 'boundedLbl', 'overflow', 'jettySize', 'sourceJettySize', 'targetJettySize',
  'orthogonalLoop', 'orthogonal', 'textDirection', 'outlineConnect', 'dropTarget',
])

type Note = (severity: Severity, feature: string, message: string) => void

/**
 * Resolve a draw.io style string over a base style. Bare tokens name
 * stylesheet entries and are merged where they appear; `key=value` pairs
 * override. Unknown names and keys are reported.
 */
function resolveStyle(raw: string, base: Style, note: Note): Style {
  const style = newStyle(base)
  for (const part of raw.split(';')) {
    const token = part.trim()
    if (token === '') continue
    const eq = token.indexOf('=')
    if (eq === -1) {
      const named = NAMED_STYLES.get(token)
      if (named === undefined) note('approximated', `style:${token}`, `named style "${token}" is not supported; ignored`)
      else Object.assign(style, named)
      continue
    }
    const key = token.slice(0, eq).trim()
    if (!RENDERED_KEYS.has(key) && !INERT_KEYS.has(key)) {
      note('approximated', `style:${key}`, `style key "${key}" is not supported; ignored`)
    }
    style[key] = token.slice(eq + 1).trim()
  }
  return style
}

const COLOR_FUNCTION = /^(?:rgb|rgba|hsl|hsla)\(\s*[0-9.%\s,/+-]+\)$/i
const PLAIN_COLOR = /^(?:#[0-9a-fA-F]{3,4}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{8}|[a-zA-Z]+)$/

/** Split `a, b` at top-level commas (commas inside parentheses are kept). */
function splitTopLevel(value: string): string[] {
  const parts: string[] = []
  let depth = 0
  let start = 0
  for (let i = 0; i < value.length; i += 1) {
    const ch = value.charAt(i)
    if (ch === '(') depth += 1
    else if (ch === ')') depth -= 1
    else if (ch === ',' && depth === 0) {
      parts.push(value.slice(start, i).trim())
      start = i + 1
    }
  }
  parts.push(value.slice(start).trim())
  return parts
}

/**
 * Resolve a draw.io colour value to an SVG paint. `default` maps to the
 * fallback, `light-dark(a, b)` to its light variant `a`; anything that is not
 * a hex, rgb/hsl or named colour is reported and replaced by the fallback.
 */
function resolveColor(value: string | undefined, fallback: string, key: string, note: Note): string {
  if (value === undefined) return fallback
  const v = value.trim()
  if (v === '' || v === 'default' || v === 'inherit') return fallback
  if (v === 'none') return 'none'
  const lightDark = /^light-dark\((.*)\)$/i.exec(v)
  if (lightDark !== null) {
    const [light] = splitTopLevel(lightDark[1] ?? '')
    return resolveColor(light, fallback, key, note)
  }
  if (PLAIN_COLOR.test(v) || COLOR_FUNCTION.test(v)) return v
  note('approximated', `color:${key}`, `${key} value "${v}" is not a supported colour; using ${fallback}`)
  return fallback
}

/** Colour for keys that are off unless set: absent or empty means none, `default` means `onDefault`. */
function optionalColor(value: string | undefined, onDefault: string, key: string, note: Note): string {
  return value === undefined || value.trim() === '' ? 'none' : resolveColor(value, onDefault, key, note)
}

/* ================================================================== *
 * Cell model
 * ================================================================== */

interface Geometry {
  x: number
  y: number
  width: number
  height: number
  relative: boolean
  points: Pt[]
  sourcePoint: Pt | null
  targetPoint: Pt | null
  offset: Pt | null
}

interface Cell {
  id: string
  parentId: string | null
  parent: Cell | null
  vertex: boolean
  edge: boolean
  label: string
  style: Style
  geometry: Geometry | null
  sourceId: string | null
  targetId: string | null
  collapsed: boolean
  visible: boolean
  children: Cell[]
}

function parsePoint(node: XmlNode): Pt {
  return { x: num(node.attrs.x, 0), y: num(node.attrs.y, 0) }
}

function parseGeometry(cellNode: XmlNode): Geometry | null {
  const node = cellNode.children.find(child => child.name === 'mxGeometry')
  if (node === undefined) return null
  const geometry: Geometry = {
    x: num(node.attrs.x, 0),
    y: num(node.attrs.y, 0),
    width: num(node.attrs.width, 0),
    height: num(node.attrs.height, 0),
    relative: node.attrs.relative === '1',
    points: [],
    sourcePoint: null,
    targetPoint: null,
    offset: null,
  }
  for (const child of node.children) {
    if (child.name === 'mxPoint') {
      if (child.attrs.as === 'sourcePoint') geometry.sourcePoint = parsePoint(child)
      else if (child.attrs.as === 'targetPoint') geometry.targetPoint = parsePoint(child)
      else if (child.attrs.as === 'offset') geometry.offset = parsePoint(child)
    } else if (child.name === 'Array' && child.attrs.as === 'points') {
      geometry.points = child.children.filter(p => p.name === 'mxPoint').map(parsePoint)
    }
  }
  return geometry
}

/**
 * Build the cell tree of one page. Cells wrapped in `<object>` or
 * `<UserObject>` take their id and label from the wrapper; with
 * `placeholders="1"`, `%name%` in the label is replaced by the wrapper's
 * attribute of that name.
 */
function buildCells(model: XmlNode, notePage: Note, noteCell: (cellId: string) => Note): Cell[] {
  const rootNode = model.children.find(child => child.name === 'root')
  if (rootNode === undefined) return []
  const byId = new Map<string, Cell>()
  const ordered: Cell[] = []

  for (const child of rootNode.children) {
    const node = child.name === 'mxCell' ? child : child.children.find(c => c.name === 'mxCell')
    if (node === undefined) continue
    const wrapper = node === child ? null : child
    const id = wrapper?.attrs.id ?? node.attrs.id ?? ''
    if (id === '' || byId.has(id)) {
      notePage('unsupported', 'cell:id', id === '' ? 'a cell without an id was skipped' : `duplicate cell id "${id}" was skipped`)
      continue
    }
    let label = wrapper === null ? node.attrs.value ?? '' : wrapper.attrs.label ?? ''
    if (wrapper !== null && wrapper.attrs.placeholders === '1') {
      const attrs = wrapper.attrs
      label = label.replace(/%([A-Za-z0-9_]+)%/g, (match, key: string) =>
        key !== 'label' && key !== 'placeholders' && key in attrs ? attrs[key] ?? match : match)
    }
    const vertex = node.attrs.vertex === '1'
    const edge = node.attrs.edge === '1'
    const base = vertex ? DEFAULT_VERTEX : edge ? DEFAULT_EDGE : newStyle()
    const cell: Cell = {
      id,
      parentId: node.attrs.parent ?? null,
      parent: null,
      vertex,
      edge,
      label,
      style: vertex || edge ? resolveStyle(node.attrs.style ?? '', base, noteCell(id)) : newStyle(),
      geometry: parseGeometry(node),
      sourceId: node.attrs.source ?? null,
      targetId: node.attrs.target ?? null,
      collapsed: node.attrs.collapsed === '1',
      visible: node.attrs.visible !== '0',
      children: [],
    }
    byId.set(id, cell)
    ordered.push(cell)
  }

  const roots: Cell[] = []
  for (const cell of ordered) {
    const parent = cell.parentId === null ? undefined : byId.get(cell.parentId)
    if (parent === undefined) {
      if (cell.parentId !== null) noteCell(cell.id)('approximated', 'cell:parent', `parent "${cell.parentId}" does not exist; drawn at top level`)
      roots.push(cell)
      continue
    }
    let ancestor: Cell | null = parent
    while (ancestor !== null && ancestor !== cell) ancestor = ancestor.parent
    if (ancestor === cell) {
      noteCell(cell.id)('unsupported', 'cell:parent', 'cell is part of a parent cycle; skipped')
      continue
    }
    cell.parent = parent
    parent.children.push(cell)
  }
  return roots
}

/* ================================================================== *
 * Text: fonts, metrics, label parsing, wrapping
 * ================================================================== */

type HAlign = 'left' | 'center' | 'right'
type VAlign = 'top' | 'middle' | 'bottom'

interface FontState {
  bold: boolean
  italic: boolean
  underline: boolean
  strike: boolean
  color: string
  size: number
  family: string
}

interface Run extends FontState { text: string }
interface Line { runs: Run[]; align: HAlign | null }

/** Helvetica/Arial advance widths for U+0020–U+007E in 1/1000 em. */
const HELVETICA_WIDTHS = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
  556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
  1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
  667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
  333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
  556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
]

const isWide = (code: number): boolean =>
  (code >= 0x1100 && code <= 0x115f) || (code >= 0x2e80 && code <= 0xa4cf) || (code >= 0xac00 && code <= 0xd7a3)
  || (code >= 0xf900 && code <= 0xfaff) || (code >= 0xfe30 && code <= 0xfe4f) || (code >= 0xff00 && code <= 0xff60)
  || (code >= 0xffe0 && code <= 0xffe6) || (code >= 0x1f300 && code <= 0x1faff)

const isMonospace = (family: string): boolean => /mono|courier|consol/i.test(family)

/** Estimated advance width in px. Labels are laid out without a font engine, so this drives wrapping and label backgrounds. */
function textWidth(text: string, font: FontState): number {
  const mono = isMonospace(font.family)
  let em = 0
  for (const ch of text) {
    const code = ch.codePointAt(0) ?? 0
    if (mono) em += isWide(code) ? 1.2 : 0.6
    else if (code >= 0x20 && code <= 0x7e) em += (HELVETICA_WIDTHS[code - 0x20] ?? 556) / 1000
    else if (code === 0xa0) em += 0.278
    else if (isWide(code)) em += 1
    else em += 0.58
  }
  return em * font.size * (font.bold ? 1.07 : 1)
}

const lineWidth = (line: Line): number => line.runs.reduce((sum, run) => sum + textWidth(run.text, run), 0)
const lineSize = (line: Line, fallback: number): number =>
  line.runs.reduce((size, run) => (run.text === '' ? size : Math.max(size, run.size)), line.runs.length > 0 ? 0 : fallback) || fallback

const HTML_ENTITIES = new Map<string, string>([
  ...XML_ENTITIES,
  ['nbsp', '\u00a0'], ['copy', '©'], ['reg', '®'], ['trade', '™'], ['ndash', '–'], ['mdash', '—'],
  ['hellip', '…'], ['laquo', '«'], ['raquo', '»'], ['lsquo', '‘'], ['rsquo', '’'], ['ldquo', '“'],
  ['rdquo', '”'], ['bull', '•'], ['middot', '·'], ['times', '×'], ['divide', '÷'], ['deg', '°'],
  ['plusmn', '±'], ['le', '≤'], ['ge', '≥'], ['ne', '≠'], ['larr', '←'], ['rarr', '→'], ['uarr', '↑'],
  ['darr', '↓'], ['harr', '↔'], ['euro', '€'], ['pound', '£'], ['yen', '¥'], ['cent', '¢'],
  ['sect', '§'], ['para', '¶'], ['micro', 'µ'], ['check', '✓'],
])

const INLINE_TAGS = new Set(['b', 'strong', 'i', 'em', 'u', 'ins', 's', 'strike', 'del', 'font', 'span', 'a', 'code', 'tt'])
const BLOCK_TAGS = new Set([
  'div', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'ul', 'ol', 'blockquote', 'pre', 'center',
  'table', 'tr', 'section', 'article', 'header', 'footer', 'hr',
])
const VOID_TAGS = new Set(['br', 'img', 'hr', 'wbr', 'input', 'meta', 'link', 'col', 'source'])
const SUPPORTED_TAG_SET = new Set(SUPPORTED_HTML_TAGS)
const HEADING_SCALE = new Map([['h1', 2], ['h2', 1.5], ['h3', 1.17], ['h4', 1], ['h5', 0.83], ['h6', 0.67]])
const HTML_FONT_SIZES = [10, 13, 16, 18, 24, 32, 48]
const TAG_PATTERN = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^\s=>/]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>"']+))?)*)\s*(\/?)>/y
const ATTR_PATTERN = /([^\s=>/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+)))?/g

const sameFont = (a: FontState, b: FontState): boolean =>
  a.bold === b.bold && a.italic === b.italic && a.underline === b.underline && a.strike === b.strike
  && a.color === b.color && a.size === b.size && a.family === b.family

function parseCssSize(value: string, current: number): number | null {
  const m = /^([0-9.]+)\s*(px|pt|em|rem|%)?$/i.exec(value.trim())
  if (m === null) return null
  const n = Number(m[1])
  if (!Number.isFinite(n)) return null
  switch ((m[2] ?? 'px').toLowerCase()) {
    case 'pt': return (n * 4) / 3
    case 'em':
    case 'rem': return n * current
    case '%': return (n * current) / 100
    default: return n
  }
}

const parseAlign = (value: string): HAlign | null => {
  const v = value.trim().toLowerCase()
  if (v === 'left' || v === 'start' || v === 'justify') return 'left'
  if (v === 'center') return 'center'
  if (v === 'right' || v === 'end') return 'right'
  return null
}

function applyCss<T extends FontState & { align: HAlign | null }>(state: T, css: string, note: Note): T {
  const next = { ...state }
  for (const declaration of css.split(';')) {
    const colon = declaration.indexOf(':')
    if (colon === -1) continue
    const prop = declaration.slice(0, colon).trim().toLowerCase()
    const value = declaration.slice(colon + 1).replace(/!important/i, '').trim()
    switch (prop) {
      case 'color':
        if (PLAIN_COLOR.test(value) || COLOR_FUNCTION.test(value)) next.color = value
        else note('approximated', 'css:color', `CSS colour "${value}" is not supported; ignored`)
        break
      case 'font-size': {
        const size = parseCssSize(value, next.size)
        if (size !== null) next.size = size
        else note('approximated', 'css:font-size', `CSS font-size "${value}" is not supported; ignored`)
        break
      }
      case 'font-weight':
        next.bold = /^(bold|bolder|[6-9]00)$/i.test(value)
        break
      case 'font-style':
        next.italic = /^(italic|oblique)/i.test(value)
        break
      case 'text-decoration':
      case 'text-decoration-line':
        next.underline = /underline/i.test(value)
        next.strike = /line-through/i.test(value)
        break
      case 'font-family':
        next.family = value.replace(/["']/g, '')
        break
      case 'text-align':
        next.align = parseAlign(value) ?? next.align
        break
      default:
        note('approximated', `css:${prop}`, `CSS property "${prop}" in a label is not supported; ignored`)
    }
  }
  return next
}

/**
 * Parse an `html=1` label into lines of styled runs.
 *
 * Steps: decode entities in text; collapse whitespace as HTML does; `<br>`
 * ends a line; block elements (div, p, h1–h6, li, …) start and end lines
 * without creating empty ones; inline elements push a style frame that the
 * matching end tag pops, restoring the previous state; unsupported tags are
 * reported and their text kept. Trailing empty lines are removed.
 */
function parseHtmlLabel(src: string, base: FontState, note: Note): Line[] {
  type State = FontState & { align: HAlign | null }
  const lines: Line[] = [{ runs: [], align: null }]
  const stack: Array<{ tag: string; saved: State }> = []
  let state: State = { ...base, align: null }
  const listCounters: number[] = []

  const current = (): Line => lines[lines.length - 1] as Line
  const hasText = (line: Line): boolean => line.runs.some(run => run.text !== '')
  const trimEnd = (line: Line): void => {
    for (let i = line.runs.length - 1; i >= 0; i -= 1) {
      const run = line.runs[i] as Run
      run.text = run.text.replace(/ +$/, '')
      if (run.text !== '') break
    }
    line.runs = line.runs.filter(run => run.text !== '')
  }
  const newline = (): void => {
    trimEnd(current())
    lines.push({ runs: [], align: null })
  }
  const blockBreak = (): void => {
    if (hasText(current())) newline()
  }
  const append = (raw: string): void => {
    let text = raw.replace(/[ \t\n\r\f]+/g, ' ')
    const line = current()
    const last = line.runs[line.runs.length - 1]
    if (!hasText(line) || (last?.text.endsWith(' ') ?? false)) text = text.replace(/^ /, '')
    if (text === '') return
    if (!hasText(line)) line.align = state.align
    if (last !== undefined && sameFont(last, state)) last.text += text
    else line.runs.push({ text, bold: state.bold, italic: state.italic, underline: state.underline, strike: state.strike, color: state.color, size: state.size, family: state.family })
  }

  let i = 0
  while (i < src.length) {
    const lt = src.indexOf('<', i)
    const end = lt === -1 ? src.length : lt
    if (end > i) append(decodeEntities(src.slice(i, end), HTML_ENTITIES))
    if (lt === -1) break
    if (src.startsWith('<!--', lt)) {
      const close = src.indexOf('-->', lt + 4)
      i = close === -1 ? src.length : close + 3
      continue
    }
    TAG_PATTERN.lastIndex = lt
    const m = TAG_PATTERN.exec(src)
    if (m === null) {
      append('<')
      i = lt + 1
      continue
    }
    i = lt + m[0].length
    const closing = m[1] === '/'
    const tag = (m[2] ?? '').toLowerCase()

    if (closing) {
      for (let k = stack.length - 1; k >= 0; k -= 1) {
        const frame = stack[k] as { tag: string; saved: State }
        if (frame.tag !== tag) continue
        state = frame.saved
        stack.length = k
        break
      }
      if (tag === 'ul' || tag === 'ol') listCounters.pop()
      if (BLOCK_TAGS.has(tag)) blockBreak()
      continue
    }

    if (!SUPPORTED_TAG_SET.has(tag)) note('approximated', `html:<${tag}>`, `HTML <${tag}> in a label is not supported; its text is kept`)
    if (tag === 'br') {
      newline()
      continue
    }
    if (BLOCK_TAGS.has(tag)) blockBreak()
    if (VOID_TAGS.has(tag) || m[4] === '/') continue
    if (!INLINE_TAGS.has(tag) && !BLOCK_TAGS.has(tag)) continue

    const attrs = new Map<string, string>()
    for (const a of (m[3] ?? '').matchAll(ATTR_PATTERN)) {
      attrs.set((a[1] ?? '').toLowerCase(), decodeEntities(a[2] ?? a[3] ?? a[4] ?? '', HTML_ENTITIES))
    }
    let next: State = { ...state }
    if (tag === 'b' || tag === 'strong') next.bold = true
    else if (tag === 'i' || tag === 'em') next.italic = true
    else if (tag === 'u' || tag === 'ins') next.underline = true
    else if (tag === 's' || tag === 'strike' || tag === 'del') next.strike = true
    else if (tag === 'code' || tag === 'tt') next.family = 'monospace'
    else if (HEADING_SCALE.has(tag)) {
      next.bold = true
      next.size = state.size * (HEADING_SCALE.get(tag) ?? 1)
    } else if (tag === 'font') {
      const color = attrs.get('color')
      if (color !== undefined && (PLAIN_COLOR.test(color) || COLOR_FUNCTION.test(color))) next.color = color
      const size = attrs.get('size')
      if (size !== undefined) {
        const rel = /^([+-])(\d)$/.exec(size)
        const level = rel === null ? Number(size) : 3 + (rel[1] === '+' ? 1 : -1) * Number(rel[2])
        if (Number.isFinite(level)) next.size = HTML_FONT_SIZES[Math.min(7, Math.max(1, Math.round(level))) - 1] ?? next.size
      }
      const face = attrs.get('face')
      if (face !== undefined) next.family = face
    } else if (tag === 'ul' || tag === 'ol') {
      listCounters.push(tag === 'ol' ? 1 : 0)
    }
    const align = attrs.get('align')
    if (align !== undefined) next.align = parseAlign(align) ?? next.align
    const css = attrs.get('style')
    if (css !== undefined) next = applyCss(next, css, note)
    stack.push({ tag, saved: state })
    state = next
    if (tag === 'li') {
      const counter = listCounters[listCounters.length - 1]
      if (counter !== undefined && counter > 0) {
        append(`${counter}. `)
        listCounters[listCounters.length - 1] = counter + 1
      } else append('• ')
    }
  }
  trimEnd(current())
  while (lines.length > 0 && !hasText(lines[lines.length - 1] as Line)) lines.pop()
  return lines
}

function parsePlainLabel(src: string, base: FontState): Line[] {
  return src.split('\n').map(text => ({ runs: [{ ...base, text }], align: null }))
}

/**
 * Greedy word wrap. Break opportunities are spaces and positions between
 * CJK characters; a word wider than the line is split by character.
 */
function wrapLine(line: Line, maxWidth: number): Line[] {
  interface Piece { run: Run; text: string; width: number; space: boolean }
  const pieces: Piece[] = []
  for (const run of line.runs) {
    for (const m of run.text.matchAll(/ +|[\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\uff00-\uff60]|[^ \u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\uff00-\uff60]+/g)) {
      const text = m[0]
      pieces.push({ run, text, width: textWidth(text, run), space: text.startsWith(' ') })
    }
  }
  const rows: Piece[][] = [[]]
  let width = 0
  const trimRow = (row: Piece[]): void => {
    while (row.length > 0 && (row[row.length - 1] as Piece).space) row.pop()
  }
  for (const piece of pieces) {
    let row = rows[rows.length - 1] as Piece[]
    if (piece.space) {
      if (row.length > 0) {
        row.push(piece)
        width += piece.width
      }
      continue
    }
    if (width + piece.width > maxWidth && row.some(p => !p.space)) {
      trimRow(row)
      row = []
      rows.push(row)
      width = 0
    }
    if (piece.width > maxWidth && row.length === 0) {
      let chunk = ''
      let chunkWidth = 0
      for (const ch of piece.text) {
        const w = textWidth(ch, piece.run)
        if (chunkWidth + w > maxWidth && chunk !== '') {
          row.push({ ...piece, text: chunk, width: chunkWidth })
          row = []
          rows.push(row)
          chunk = ''
          chunkWidth = 0
        }
        chunk += ch
        chunkWidth += w
      }
      row.push({ ...piece, text: chunk, width: chunkWidth })
      width = chunkWidth
      continue
    }
    row.push(piece)
    width += piece.width
  }
  trimRow(rows[rows.length - 1] as Piece[])
  return rows.map(row => {
    const runs: Run[] = []
    for (const piece of row) {
      const last = runs[runs.length - 1]
      if (last !== undefined && sameFont(last, piece.run)) last.text += piece.text
      else runs.push({ ...piece.run, text: piece.text })
    }
    return { runs, align: line.align }
  })
}

/* ================================================================== *
 * Render context
 * ================================================================== */

interface Frame {
  box: Box
  center: Pt
  /** Rotation and flips about the centre: maps cell-box coordinates to the page. */
  cellMat: Mat
  /** cellMat plus `direction`: maps shape-box coordinates to the page. */
  shapeMat: Mat
  shapeBox: Box
  kind: string
  outline: Pt[]
  bounds: Box
}

class Context {
  readonly diagnostics: Diagnostic[] = []
  readonly defs: string[] = []
  readonly body: string[] = []
  readonly bounds = new Bounds()
  readonly frames = new Map<string, Frame | null>()
  drawn = 0
  readonly idPrefix: string
  readonly fallbackFonts: string
  private readonly seen = new Set<string>()
  private nextId = 0

  constructor(idPrefix: string, fallbackFonts: string) {
    this.idPrefix = idPrefix
    this.fallbackFonts = fallbackFonts
  }

  note(cellId: string | null): Note {
    return (severity, feature, message) => {
      const key = `${cellId ?? ''}\u0000${feature}`
      if (this.seen.has(key)) return
      this.seen.add(key)
      this.diagnostics.push({ severity, cellId, feature, message })
    }
  }

  newId(kind: string): string {
    this.nextId += 1
    return `${this.idPrefix}-${kind}${this.nextId}`
  }

  fontFamily(family: string): string {
    const names = [...family.split(','), ...this.fallbackFonts.split(',')]
      .map(name => name.trim().replace(/^["']|["']$/g, ''))
      .filter(name => name !== '')
    return [...new Set(names)].map(name => (/[^A-Za-z0-9-]/.test(name) ? `'${name}'` : name)).join(', ')
  }
}

/* ================================================================== *
 * Text rendering
 * ================================================================== */

interface TextBlock {
  lines: Line[]
  base: FontState
  /** Box the text is aligned in, before `transform`. */
  box: Box
  align: HAlign
  valign: VAlign
  wrap: boolean
  transform: Mat
  background: string
  border: string
  opacity: number
  preserveSpace: boolean
}

function fontFromStyle(style: Style, note: Note): FontState {
  const flags = num(style.fontStyle, 0)
  return {
    bold: (flags & 1) !== 0,
    italic: (flags & 2) !== 0,
    underline: (flags & 4) !== 0,
    strike: (flags & 8) !== 0,
    color: resolveColor(style.fontColor, '#000000', 'fontColor', note),
    size: Math.max(1, num(style.fontSize, 12)),
    family: style.fontFamily ?? 'Helvetica',
  }
}

/**
 * Emit a text block: one `<text>` per line inside a group carrying the base
 * font, with `<tspan>`s only where a run differs from the base. Lines are
 * 1.2 em tall; each baseline sits so capitals centre on the line box.
 */
function renderText(ctx: Context, block: TextBlock): void {
  const { box, base } = block
  const lines = block.wrap && box.w > 0 ? block.lines.flatMap(line => wrapLine(line, box.w)) : block.lines
  if (lines.length === 0) return
  const metrics = lines.map(line => ({ size: lineSize(line, base.size), width: lineWidth(line) }))
  const height = metrics.reduce((sum, m) => sum + m.size * 1.2, 0)
  const blockWidth = block.wrap && box.w > 0 ? box.w : Math.max(...metrics.map(m => m.width))
  const top = block.valign === 'top' ? box.y : block.valign === 'bottom' ? box.y + box.h - height : box.y + (box.h - height) / 2
  const left = block.align === 'left' ? box.x : block.align === 'right' ? box.x + box.w - blockWidth : box.x + (box.w - blockWidth) / 2

  const parts: string[] = []
  const frame = { x: left - 2, y: top, w: blockWidth + 4, h: height }
  if (block.background !== 'none' || block.border !== 'none') {
    parts.push(`<rect x="${fmt(frame.x)}" y="${fmt(frame.y)}" width="${fmt(frame.w)}" height="${fmt(frame.h)}" fill="${esc(block.background)}" stroke="${esc(block.border)}"/>`)
  }
  let y = top
  lines.forEach((line, index) => {
    const m = metrics[index] ?? { size: base.size, width: 0 }
    const lineHeight = m.size * 1.2
    if (line.runs.some(run => run.text !== '')) {
      const align = line.align ?? block.align
      const x = align === 'left' ? left : align === 'right' ? left + blockWidth : left + blockWidth / 2
      const anchor = align === 'left' ? 'start' : align === 'right' ? 'end' : 'middle'
      const spans = line.runs.map(run => {
        let attrs = ''
        if (run.size !== base.size) attrs += ` font-size="${fmt(run.size)}"`
        if (run.bold !== base.bold) attrs += ` font-weight="${run.bold ? 'bold' : 'normal'}"`
        if (run.italic !== base.italic) attrs += ` font-style="${run.italic ? 'italic' : 'normal'}"`
        if (run.color !== base.color) attrs += ` fill="${esc(run.color)}"`
        if (run.family !== base.family) attrs += ` font-family="${esc(ctx.fontFamily(run.family))}"`
        const decorations = [run.underline ? 'underline' : '', run.strike ? 'line-through' : ''].filter(Boolean).join(' ')
        if (decorations !== '') attrs += ` text-decoration="${decorations}"`
        return attrs === '' ? esc(run.text) : `<tspan${attrs}>${esc(run.text)}</tspan>`
      })
      parts.push(`<text x="${fmt(x)}" y="${fmt(y + lineHeight / 2 + m.size * 0.36)}" text-anchor="${anchor}">${spans.join('')}</text>`)
    }
    y += lineHeight
  })

  let attrs = ` font-family="${esc(ctx.fontFamily(base.family))}" font-size="${fmt(base.size)}" fill="${esc(base.color)}"`
  if (base.bold) attrs += ' font-weight="bold"'
  if (base.italic) attrs += ' font-style="italic"'
  if (block.opacity < 100) attrs += ` opacity="${fmt(Math.max(0, block.opacity) / 100)}"`
  if (block.preserveSpace) attrs += ' xml:space="preserve"'
  ctx.body.push(`<g${attrs}${matAttr(block.transform)}>${parts.join('')}</g>`)
  ctx.bounds.addBox(frame, block.transform)
}

const H_ALIGNS = new Set(['left', 'center', 'right'])
const V_ALIGNS = new Set(['top', 'middle', 'bottom'])

function enumValue<T extends string>(style: Style, key: string, allowed: Set<string>, fallback: T, note: Note): T {
  const value = style[key]
  if (value === undefined || value === '') return fallback
  if (allowed.has(value)) return value as T
  note('approximated', `${key}=${value}`, `${key} "${value}" is not supported; using ${fallback}`)
  return fallback
}

function parseLabel(label: string, style: Style, base: FontState, note: Note): { lines: Line[]; html: boolean } {
  const html = style.html === '1'
  return { lines: html ? parseHtmlLabel(label, base, note) : parsePlainLabel(label, base), html }
}

/* ================================================================== *
 * Vertices
 * ================================================================== */

const SHAPE_SET = new Set(SUPPORTED_SHAPES)
const DIRECTIONS = new Map([['east', 0], ['south', 90], ['west', 180], ['north', 270]])

function shapeKind(style: Style, note: Note): string {
  const shape = style.shape ?? 'rectangle'
  const kind = shape === 'rect' ? 'rectangle' : shape
  if (SHAPE_SET.has(kind)) return kind
  note('unsupported', `shape=${shape}`, `shape "${shape}" is not supported; drawn as a placeholder`)
  return 'unsupported'
}

/** Size parameter shared by hexagon, parallelogram, trapezoid and process: a fraction of the width, or px with fixedSize=1. */
function insetSize(style: Style, w: number, fraction: number, fixed: number): number {
  if (style.fixedSize === '1') return Math.max(0, Math.min(w / 2, num(style.size, fixed)))
  return w * Math.max(0, Math.min(1, num(style.size, fraction)))
}

function polygonPoints(kind: string, b: Box, style: Style): Pt[] | null {
  const { x, y, w, h } = b
  switch (kind) {
    case 'rhombus':
      return [{ x: x + w / 2, y }, { x: x + w, y: y + h / 2 }, { x: x + w / 2, y: y + h }, { x, y: y + h / 2 }]
    case 'triangle':
      return [{ x, y }, { x: x + w, y: y + h / 2 }, { x, y: y + h }]
    case 'hexagon': {
      const d = insetSize(style, w, 0.25, 20)
      return [{ x: x + d, y }, { x: x + w - d, y }, { x: x + w, y: y + h / 2 }, { x: x + w - d, y: y + h }, { x: x + d, y: y + h }, { x, y: y + h / 2 }]
    }
    case 'parallelogram': {
      const d = insetSize(style, w, 0.2, 20)
      return [{ x, y: y + h }, { x: x + d, y }, { x: x + w, y }, { x: x + w - d, y: y + h }]
    }
    case 'trapezoid': {
      const d = insetSize(style, w, 0.2, 20)
      return [{ x, y: y + h }, { x: x + d, y }, { x: x + w - d, y }, { x: x + w, y: y + h }]
    }
    default:
      return null
  }
}

function ellipsePoints(b: Box, count = 48): Pt[] {
  const c = center(b)
  return Array.from({ length: count }, (_, i) => {
    const a = (i / count) * Math.PI * 2
    return { x: c.x + (Math.cos(a) * b.w) / 2, y: c.y + (Math.sin(a) * b.h) / 2 }
  })
}

/** Closed polygon path; with r > 0 each corner is cut back by up to r and joined with a quadratic curve. */
function polygonPath(points: Pt[], r: number): string {
  if (r <= 0) return `M ${points.map(fmtPt).join(' L ')} Z`
  const n = points.length
  let d = ''
  for (let i = 0; i < n; i += 1) {
    const prev = points[(i + n - 1) % n] as Pt
    const cur = points[i] as Pt
    const next = points[(i + 1) % n] as Pt
    const toward = (p: Pt): Pt => {
      const len = Math.hypot(p.x - cur.x, p.y - cur.y)
      const t = len === 0 ? 0 : Math.min(r, len / 2) / len
      return { x: cur.x + (p.x - cur.x) * t, y: cur.y + (p.y - cur.y) * t }
    }
    d += `${i === 0 ? 'M' : ' L'} ${fmtPt(toward(prev))} Q ${fmtPt(cur)} ${fmtPt(toward(next))}`
  }
  return `${d} Z`
}

function rectCornerRadius(style: Style, w: number, h: number): number {
  if (style.rounded !== '1') return 0
  const r = style.absoluteArcSize === '1' ? num(style.arcSize, 20) / 2 : (Math.min(w, h) * num(style.arcSize, 15)) / 100
  return Math.max(0, Math.min(r, w / 2, h / 2))
}

/** Absolute box of a vertex: parent origin plus geometry, or a fraction of the parent's size for relative geometry. */
function absoluteBox(cell: Cell, cache: Map<string, Box | null>): Box | null {
  if (cache.has(cell.id)) return cache.get(cell.id) ?? null
  cache.set(cell.id, null)
  const g = cell.geometry
  if (!cell.vertex || g === null) return null
  const parent = cell.parent !== null && cell.parent.vertex ? absoluteBox(cell.parent, cache) : null
  const ox = parent?.x ?? 0
  const oy = parent?.y ?? 0
  const box = g.relative && parent !== null
    ? { x: ox + g.x * parent.w + (g.offset?.x ?? 0), y: oy + g.y * parent.h + (g.offset?.y ?? 0), w: g.width, h: g.height }
    : { x: ox + g.x, y: oy + g.y, w: g.width, h: g.height }
  cache.set(cell.id, box)
  return box
}

function originOf(cell: Cell, boxes: Map<string, Box | null>): Pt {
  const parent = cell.parent
  if (parent === null || !parent.vertex) return { x: 0, y: 0 }
  const box = absoluteBox(parent, boxes)
  return box === null ? { x: 0, y: 0 } : { x: box.x, y: box.y }
}

function computeFrame(cell: Cell, boxes: Map<string, Box | null>, note: Note): Frame | null {
  const box = absoluteBox(cell, boxes)
  if (box === null) return null
  const style = cell.style
  const kind = shapeKind(style, note)
  const c = center(box)
  const direction = style.direction ?? 'east'
  let dirDeg = DIRECTIONS.get(direction)
  if (dirDeg === undefined) {
    note('approximated', `direction=${direction}`, `direction "${direction}" is not supported; using east`)
    dirDeg = 0
  }
  if (kind === 'swimlane') dirDeg = 0
  const swapped = dirDeg === 90 || dirDeg === 270
  const shapeBox = swapped ? { x: c.x - box.h / 2, y: c.y - box.w / 2, w: box.h, h: box.w } : box
  const flip = scaleAbout(style.flipH === '1' ? -1 : 1, style.flipV === '1' ? -1 : 1, c)
  const cellMat = mul(rotateAbout(num(style.rotation, 0), c), flip)
  const shapeMat = mul(cellMat, rotateAbout(dirDeg, c))
  const local = kind === 'ellipse' || kind === 'doubleEllipse'
    ? ellipsePoints(shapeBox)
    : polygonPoints(kind, shapeBox, style) ?? corners(shapeBox)
  const outline = local.map(p => apply(shapeMat, p))
  return { box, center: c, cellMat, shapeMat, shapeBox, kind, outline, bounds: aabb(outline) }
}

interface Paint { fill: string; stroke: string; attrs: string; strokeWidth: number }

function paint(ctx: Context, style: Style, note: Note, fillable: boolean): Paint {
  let fill = fillable ? resolveColor(style.fillColor, '#ffffff', 'fillColor', note) : 'none'
  const stroke = resolveColor(style.strokeColor, '#000000', 'strokeColor', note)
  const strokeWidth = Math.max(0, num(style.strokeWidth, 1))
  if (fill !== 'none') {
    const gradient = optionalColor(style.gradientColor, '#ffffff', 'gradientColor', note)
    if (gradient !== 'none') {
      const id = ctx.newId('g')
      const dir = style.gradientDirection ?? 'south'
      const [x1, y1, x2, y2] = dir === 'north' ? [0, 1, 0, 0] : dir === 'east' ? [0, 0, 1, 0] : dir === 'west' ? [1, 0, 0, 0] : [0, 0, 0, 1]
      ctx.defs.push(`<linearGradient id="${esc(id)}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"><stop offset="0" stop-color="${esc(fill)}"/><stop offset="1" stop-color="${esc(gradient)}"/></linearGradient>`)
      fill = `url(#${id})`
    }
  }
  let attrs = ` fill="${esc(fill)}" stroke="${esc(stroke)}" stroke-width="${fmt(strokeWidth)}"`
  if (style.dashed === '1') {
    const pattern = /^[0-9.]+(\s+[0-9.]+)*$/.test(style.dashPattern ?? '') ? (style.dashPattern ?? '') : '3 3'
    const scale = style.fixDash === '1' ? 1 : Math.max(1, strokeWidth)
    attrs += ` stroke-dasharray="${pattern.split(/\s+/).map(v => fmt(Number(v) * scale)).join(' ')}"`
  }
  const fillOpacity = num(style.fillOpacity, 100)
  const strokeOpacity = num(style.strokeOpacity, 100)
  if (fillOpacity < 100) attrs += ` fill-opacity="${fmt(Math.max(0, fillOpacity) / 100)}"`
  if (strokeOpacity < 100) attrs += ` stroke-opacity="${fmt(Math.max(0, strokeOpacity) / 100)}"`
  return { fill, stroke, attrs, strokeWidth }
}

function swimlaneElements(ctx: Context, style: Style, b: Box, note: Note): { svg: string; header: Box } {
  const horizontal = style.horizontal !== '0'
  const start = Math.max(0, Math.min(horizontal ? b.h : b.w, num(style.startSize, 40)))
  const p = paint(ctx, style, note, true)
  const bodyFill = optionalColor(style.swimlaneFillColor, '#ffffff', 'swimlaneFillColor', note)
  const header = horizontal ? { x: b.x, y: b.y, w: b.w, h: start } : { x: b.x, y: b.y, w: start, h: b.h }
  const body = horizontal ? { x: b.x, y: b.y + start, w: b.w, h: b.h - start } : { x: b.x + start, y: b.y, w: b.w - start, h: b.h }
  const rounded = style.rounded === '1'
  const r = !rounded ? 0 : style.absoluteArcSize === '1'
    ? Math.min(num(style.arcSize, 20) / 2, start / 2)
    : (Math.min(horizontal ? b.w : b.h, start) * num(style.arcSize, 15)) / 100
  const round = (box: Box, which: 'all' | 'header' | 'body'): string => {
    const rr = Math.max(0, Math.min(r, box.w / 2, box.h / 2))
    const [tl, tr, br, bl] = which === 'all' ? [rr, rr, rr, rr]
      : which === 'header' ? (horizontal ? [rr, rr, 0, 0] : [rr, 0, 0, rr])
        : horizontal ? [0, 0, rr, rr] : [0, rr, rr, 0]
    const { x, y, w, h } = box
    return `M ${fmt(x + tl)} ${fmt(y)} L ${fmt(x + w - tr)} ${fmt(y)}${tr > 0 ? ` A ${fmt(tr)} ${fmt(tr)} 0 0 1 ${fmt(x + w)} ${fmt(y + tr)}` : ''}`
      + ` L ${fmt(x + w)} ${fmt(y + h - br)}${br > 0 ? ` A ${fmt(br)} ${fmt(br)} 0 0 1 ${fmt(x + w - br)} ${fmt(y + h)}` : ''}`
      + ` L ${fmt(x + bl)} ${fmt(y + h)}${bl > 0 ? ` A ${fmt(bl)} ${fmt(bl)} 0 0 1 ${fmt(x)} ${fmt(y + h - bl)}` : ''}`
      + ` L ${fmt(x)} ${fmt(y + tl)}${tl > 0 ? ` A ${fmt(tl)} ${fmt(tl)} 0 0 1 ${fmt(x + tl)} ${fmt(y)}` : ''} Z`
  }
  const strokeOnly = p.attrs.replace(/ fill="[^"]*"/, ' fill="none"')
  let svg = ''
  if (bodyFill !== 'none' && body.w > 0 && body.h > 0) svg += `<path d="${round(body, 'body')}" fill="${esc(bodyFill)}" stroke="none"/>`
  if (p.fill !== 'none' && start > 0) svg += `<path d="${round(header, 'header')}" fill="${esc(p.fill)}" stroke="none"/>`
  svg += `<path d="${round(b, 'all')}"${strokeOnly}/>`
  if (style.swimlaneLine !== '0' && start > 0 && start < (horizontal ? b.h : b.w)) {
    const line = horizontal
      ? `M ${fmt(b.x)} ${fmt(b.y + start)} L ${fmt(b.x + b.w)} ${fmt(b.y + start)}`
      : `M ${fmt(b.x + start)} ${fmt(b.y)} L ${fmt(b.x + start)} ${fmt(b.y + b.h)}`
    svg += `<path d="${line}"${strokeOnly}/>`
  }
  return { svg, header }
}

/** Shape elements in shape-box coordinates; `header` is set for swimlanes, whose label sits in the header. */
function shapeElements(ctx: Context, cell: Cell, frame: Frame, note: Note): { svg: string; header: Box | null } {
  const style = cell.style
  const b = frame.shapeBox
  const { x, y, w, h } = b
  const p = paint(ctx, style, note, frame.kind !== 'line')
  const strokeOnly = p.attrs.replace(/ fill="[^"]*"/, ' fill="none"')
  switch (frame.kind) {
    case 'rectangle': {
      const r = rectCornerRadius(style, w, h)
      return { svg: `<rect x="${fmt(x)}" y="${fmt(y)}" width="${fmt(w)}" height="${fmt(h)}"${r > 0 ? ` rx="${fmt(r)}" ry="${fmt(r)}"` : ''}${p.attrs}/>`, header: null }
    }
    case 'ellipse':
      return { svg: `<ellipse cx="${fmt(x + w / 2)}" cy="${fmt(y + h / 2)}" rx="${fmt(w / 2)}" ry="${fmt(h / 2)}"${p.attrs}/>`, header: null }
    case 'doubleEllipse': {
      const inset = Math.max(0, num(style.margin, Math.min(3 + p.strokeWidth, Math.min(w / 5, h / 5))))
      return {
        svg: `<ellipse cx="${fmt(x + w / 2)}" cy="${fmt(y + h / 2)}" rx="${fmt(w / 2)}" ry="${fmt(h / 2)}"${p.attrs}/>`
          + `<ellipse cx="${fmt(x + w / 2)}" cy="${fmt(y + h / 2)}" rx="${fmt(Math.max(0, w / 2 - inset))}" ry="${fmt(Math.max(0, h / 2 - inset))}"${strokeOnly}/>`,
        header: null,
      }
    }
    case 'rhombus':
    case 'triangle':
    case 'hexagon':
    case 'parallelogram':
    case 'trapezoid': {
      const points = polygonPoints(frame.kind, b, style) ?? corners(b)
      const r = style.rounded === '1' ? num(style.arcSize, 20) / 2 : 0
      return { svg: `<path d="${polygonPath(points, r)}"${p.attrs}/>`, header: null }
    }
    case 'cylinder3': {
      const dy = Math.max(0, Math.min(h / 2, num(style.size, 15)))
      const outer = `M ${fmt(x)} ${fmt(y + dy)} A ${fmt(w / 2)} ${fmt(dy)} 0 0 1 ${fmt(x + w)} ${fmt(y + dy)} L ${fmt(x + w)} ${fmt(y + h - dy)} A ${fmt(w / 2)} ${fmt(dy)} 0 0 1 ${fmt(x)} ${fmt(y + h - dy)} Z`
      const front = `M ${fmt(x)} ${fmt(y + dy)} A ${fmt(w / 2)} ${fmt(dy)} 0 0 0 ${fmt(x + w)} ${fmt(y + dy)}`
      return { svg: `<path d="${outer}"${p.attrs}/><path d="${front}"${strokeOnly}/>`, header: null }
    }
    case 'cylinder': {
      const dy = Math.min(40, Math.round(h / 5))
      const outer = `M ${fmt(x)} ${fmt(y + dy)} C ${fmt(x)} ${fmt(y - dy / 3)} ${fmt(x + w)} ${fmt(y - dy / 3)} ${fmt(x + w)} ${fmt(y + dy)} L ${fmt(x + w)} ${fmt(y + h - dy)} C ${fmt(x + w)} ${fmt(y + h + dy / 3)} ${fmt(x)} ${fmt(y + h + dy / 3)} ${fmt(x)} ${fmt(y + h - dy)} Z`
      const front = `M ${fmt(x)} ${fmt(y + dy)} C ${fmt(x)} ${fmt(y + 2 * dy)} ${fmt(x + w)} ${fmt(y + 2 * dy)} ${fmt(x + w)} ${fmt(y + dy)}`
      return { svg: `<path d="${outer}"${p.attrs}/><path d="${front}"${strokeOnly}/>`, header: null }
    }
    case 'process': {
      const d = insetSize(style, w, 0.1, 20)
      const bars = `M ${fmt(x + d)} ${fmt(y)} L ${fmt(x + d)} ${fmt(y + h)} M ${fmt(x + w - d)} ${fmt(y)} L ${fmt(x + w - d)} ${fmt(y + h)}`
      return { svg: `<rect x="${fmt(x)}" y="${fmt(y)}" width="${fmt(w)}" height="${fmt(h)}"${p.attrs}/><path d="${bars}"${strokeOnly}/>`, header: null }
    }
    case 'document': {
      const dy = h * Math.max(0, Math.min(1, num(style.size, 0.3)))
      const d = `M ${fmt(x)} ${fmt(y)} L ${fmt(x + w)} ${fmt(y)} L ${fmt(x + w)} ${fmt(y + h - dy / 2)} Q ${fmt(x + (w * 3) / 4)} ${fmt(y + h - dy * 1.4)} ${fmt(x + w / 2)} ${fmt(y + h - dy / 2)} Q ${fmt(x + w / 4)} ${fmt(y + h + dy * 0.4)} ${fmt(x)} ${fmt(y + h - dy / 2)} Z`
      return { svg: `<path d="${d}"${p.attrs}/>`, header: null }
    }
    case 'line':
      return { svg: `<path d="M ${fmt(x)} ${fmt(y + h / 2)} L ${fmt(x + w)} ${fmt(y + h / 2)}"${strokeOnly}/>`, header: null }
    case 'swimlane':
      return swimlaneElements(ctx, style, b, note)
    default: {
      const name = style.shape ?? ''
      const tag = name === '' ? '' : `<text x="${fmt(x + 3)}" y="${fmt(y + 10)}" font-family="${esc(ctx.fontFamily('Helvetica'))}" font-size="8" fill="#888888">${esc(name)}</text>`
      return { svg: `<rect x="${fmt(x)}" y="${fmt(y)}" width="${fmt(w)}" height="${fmt(h)}" fill="none" stroke="#888888" stroke-dasharray="4 3"/>${tag}`, header: null }
    }
  }
}

function renderVertex(ctx: Context, cell: Cell, frame: Frame, note: Note): void {
  const style = cell.style
  const { svg, header } = shapeElements(ctx, cell, frame, note)
  const opacity = num(style.opacity, 100)
  const opacityAttr = opacity < 100 ? ` opacity="${fmt(Math.max(0, opacity) / 100)}"` : ''
  ctx.body.push(isIdentity(frame.shapeMat) && opacityAttr === '' ? svg : `<g${opacityAttr}${matAttr(frame.shapeMat)}>${svg}</g>`)
  for (const p of frame.outline) ctx.bounds.add(p)
  ctx.drawn += 1
  if (cell.label !== '' && style.noLabel !== '1') renderVertexLabel(ctx, cell, frame, header, note)
}

/**
 * Lay out a vertex label: start from the cell box (or the swimlane header,
 * or below a cylinder3's cap with boundedLbl=1), move it beside the shape for labelPosition / verticalLabelPosition, inset
 * it by the spacing keys, then rotate with the cell and by -90° when
 * horizontal=0.
 */
function renderVertexLabel(ctx: Context, cell: Cell, frame: Frame, header: Box | null, note: Note): void {
  const style = cell.style
  let box = header ?? frame.box
  if (frame.kind === 'cylinder3' && style.boundedLbl === '1') {
    const cap = 2 * Math.max(0, Math.min(box.h / 2, num(style.size, 15)))
    box = { x: box.x, y: box.y + cap, w: box.w, h: Math.max(0, box.h - cap) }
  }
  const labelPosition = enumValue<HAlign>(style, 'labelPosition', H_ALIGNS, 'center', note)
  const verticalLabelPosition = enumValue<VAlign>(style, 'verticalLabelPosition', V_ALIGNS, 'middle', note)
  const outer = {
    x: box.x + (labelPosition === 'left' ? -box.w : labelPosition === 'right' ? box.w : 0),
    y: box.y + (verticalLabelPosition === 'top' ? -box.h : verticalLabelPosition === 'bottom' ? box.h : 0),
    w: box.w,
    h: box.h,
  }
  const spacing = num(style.spacing, 2)
  const left = spacing + num(style.spacingLeft, 0)
  const right = spacing + num(style.spacingRight, 0)
  const top = spacing + num(style.spacingTop, 0)
  const bottom = spacing + num(style.spacingBottom, 0)
  let inner = { x: outer.x + left, y: outer.y + top, w: Math.max(0, outer.w - left - right), h: Math.max(0, outer.h - top - bottom) }
  let transform = rotateAbout(num(style.rotation, 0), frame.center)
  if (style.horizontal === '0') {
    const c = center(inner)
    inner = { x: c.x - inner.h / 2, y: c.y - inner.w / 2, w: inner.h, h: inner.w }
    transform = mul(transform, rotateAbout(-90, c))
  }
  const base = fontFromStyle(style, note)
  const { lines, html } = parseLabel(cell.label, style, base, note)
  renderText(ctx, {
    lines,
    base,
    box: inner,
    align: enumValue<HAlign>(style, 'align', H_ALIGNS, 'center', note),
    valign: enumValue<VAlign>(style, 'verticalAlign', V_ALIGNS, 'middle', note),
    wrap: style.whiteSpace === 'wrap',
    transform,
    background: optionalColor(style.labelBackgroundColor, '#ffffff', 'labelBackgroundColor', note),
    border: optionalColor(style.labelBorderColor, '#000000', 'labelBorderColor', note),
    opacity: num(style.textOpacity, 100),
    preserveSpace: !html,
  })
}

/* ================================================================== *
 * Edges
 * ================================================================== */

interface Port { pt: Pt; dir: Pt }
type Side = 'left' | 'right' | 'top' | 'bottom'

const SIDE_DIR: Record<Side, Pt> = { left: { x: -1, y: 0 }, right: { x: 1, y: 0 }, top: { x: 0, y: -1 }, bottom: { x: 0, y: 1 } }
const ARROW_SET = new Set(SUPPORTED_ARROWS)
const EDGE_STYLE_SET = new Set(SUPPORTED_EDGE_STYLES)

/** Intersections of the infinite line p + t·dir with a closed polygon, as values of t. */
function lineHits(poly: Pt[], p: Pt, dir: Pt): number[] {
  const hits: number[] = []
  for (let i = 0; i < poly.length; i += 1) {
    const a = poly[i] as Pt
    const b = poly[(i + 1) % poly.length] as Pt
    const ex = b.x - a.x
    const ey = b.y - a.y
    const denom = dir.x * ey - dir.y * ex
    if (Math.abs(denom) < 1e-12) continue
    const t = ((a.x - p.x) * ey - (a.y - p.y) * ex) / denom
    const s = ((a.x - p.x) * dir.y - (a.y - p.y) * dir.x) / denom
    if (s >= -1e-9 && s <= 1 + 1e-9) hits.push(t)
  }
  return hits
}

/** Where the ray from the shape's centre toward `toward` leaves the outline. */
function perimeterPoint(frame: Frame, toward: Pt): Pt {
  const dir = { x: toward.x - frame.center.x, y: toward.y - frame.center.y }
  if (Math.hypot(dir.x, dir.y) < 1e-9) return frame.center
  const ts = lineHits(frame.outline, frame.center, dir).filter(t => t > 1e-9)
  if (ts.length === 0) return frame.center
  const t = Math.min(...ts)
  return { x: frame.center.x + dir.x * t, y: frame.center.y + dir.y * t }
}

/** Slide p along dir's axis to the outermost outline point in direction dir. */
function projectOnAxis(frame: Frame, p: Pt, dir: Pt): Pt {
  const ts = lineHits(frame.outline, p, dir)
  if (ts.length === 0) return p
  const t = Math.max(...ts)
  return { x: p.x + dir.x * t, y: p.y + dir.y * t }
}

function sidePort(frame: Frame, side: Side): Port {
  const b = frame.bounds
  const c = center(b)
  const anchor = side === 'left' ? { x: b.x, y: c.y } : side === 'right' ? { x: b.x + b.w, y: c.y } : side === 'top' ? { x: c.x, y: b.y } : { x: c.x, y: b.y + b.h }
  const dir = SIDE_DIR[side]
  return { pt: projectOnAxis(frame, { x: anchor.x - dir.x * b.w, y: anchor.y - dir.y * b.h }, dir), dir }
}

/** Sides facing each other: horizontal when the horizontal gap between the boxes is at least the vertical one. */
function facingSides(a: Box, b: Box, axis: 'auto' | 'horizontal' | 'vertical' = 'auto'): [Side, Side] {
  const gapX = Math.max(b.x - (a.x + a.w), a.x - (b.x + b.w))
  const gapY = Math.max(b.y - (a.y + a.h), a.y - (b.y + b.h))
  const ca = center(a)
  const cb = center(b)
  const horizontal = axis === 'horizontal' || (axis === 'auto' && gapX >= gapY)
  if (horizontal) return cb.x >= ca.x ? ['right', 'left'] : ['left', 'right']
  return cb.y >= ca.y ? ['bottom', 'top'] : ['top', 'bottom']
}

function snapDir(v: Pt): Pt {
  return Math.abs(v.x) >= Math.abs(v.y) ? { x: Math.sign(v.x) || 1, y: 0 } : { x: 0, y: Math.sign(v.y) || 1 }
}

/** Fixed connection point from exitX/exitY (or entryX/entryY), projected onto the outline unless the perimeter flag is 0. */
function constraintPort(frame: Frame, style: Style, prefix: 'exit' | 'entry'): Port | null {
  const fx = Number(style[`${prefix}X`])
  const fy = Number(style[`${prefix}Y`])
  if (style[`${prefix}X`] === undefined || style[`${prefix}Y`] === undefined || !Number.isFinite(fx) || !Number.isFinite(fy)) return null
  const b = frame.box
  const local = { x: b.x + fx * b.w + num(style[`${prefix}Dx`], 0), y: b.y + fy * b.h + num(style[`${prefix}Dy`], 0) }
  const distances: Array<[Side, number]> = [['left', fx], ['right', 1 - fx], ['top', fy], ['bottom', 1 - fy]]
  distances.sort((p, q) => p[1] - q[1])
  const side = (distances[0] as [Side, number])[0]
  const dir = snapDir(applyLinear(frame.cellMat, SIDE_DIR[side]))
  const abs = apply(frame.cellMat, local)
  const pt = style[`${prefix}Perimeter`] === '0' ? abs : perimeterPoint(frame, abs)
  return { pt, dir }
}

/**
 * Orthogonal route between two ports. Facing ports get a Z through the
 * midline; same-direction ports a U beyond the further stub; perpendicular
 * ports an L when the corner lies ahead of both, otherwise a detour via
 * stubs of length `stub`.
 */
function orthogonalRoute(p0: Pt, d0: Pt, p1: Pt, d1: Pt, stub: number): Pt[] {
  const a = { x: p0.x + d0.x * stub, y: p0.y + d0.y * stub }
  const b = { x: p1.x + d1.x * stub, y: p1.y + d1.y * stub }
  const h0 = d0.y === 0
  const h1 = d1.y === 0
  if (h0 && h1) {
    if (d0.x !== d1.x && (p1.x - p0.x) * d0.x > 0) {
      const mx = (p0.x + p1.x) / 2
      return [p0, { x: mx, y: p0.y }, { x: mx, y: p1.y }, p1]
    }
    if (d0.x === d1.x) {
      const x = d0.x > 0 ? Math.max(a.x, b.x) : Math.min(a.x, b.x)
      return [p0, { x, y: p0.y }, { x, y: p1.y }, p1]
    }
    const my = (p0.y + p1.y) / 2
    return [p0, a, { x: a.x, y: my }, { x: b.x, y: my }, b, p1]
  }
  if (!h0 && !h1) {
    if (d0.y !== d1.y && (p1.y - p0.y) * d0.y > 0) {
      const my = (p0.y + p1.y) / 2
      return [p0, { x: p0.x, y: my }, { x: p1.x, y: my }, p1]
    }
    if (d0.y === d1.y) {
      const y = d0.y > 0 ? Math.max(a.y, b.y) : Math.min(a.y, b.y)
      return [p0, { x: p0.x, y }, { x: p1.x, y }, p1]
    }
    const mx = (p0.x + p1.x) / 2
    return [p0, a, { x: mx, y: a.y }, { x: mx, y: b.y }, b, p1]
  }
  if (h0) {
    const corner = { x: p1.x, y: p0.y }
    if ((corner.x - p0.x) * d0.x > 0 && (corner.y - p1.y) * d1.y > 0) return [p0, corner, p1]
    return [p0, a, { x: a.x, y: b.y }, b, p1]
  }
  const corner = { x: p0.x, y: p1.y }
  if ((corner.y - p0.y) * d0.y > 0 && (corner.x - p1.x) * d1.x > 0) return [p0, corner, p1]
  return [p0, a, { x: b.x, y: a.y }, b, p1]
}

/** Orthogonal path from a port through waypoints to a port, inserting one elbow wherever consecutive points are not aligned. */
function orthogonalThrough(start: Port, waypoints: Pt[], end: Port): Pt[] {
  const points = [start.pt]
  let horizontal = start.dir.y === 0
  const targets = [...waypoints, end.pt]
  targets.forEach((t, index) => {
    const cur = points[points.length - 1] as Pt
    if (near(cur.x, t.x) || near(cur.y, t.y)) {
      points.push(t)
      horizontal = near(cur.y, t.y)
      return
    }
    const lastLeg = index === targets.length - 1
    const elbow = lastLeg
      ? (end.dir.y === 0 ? { x: cur.x, y: t.y } : { x: t.x, y: cur.y })
      : (horizontal ? { x: t.x, y: cur.y } : { x: cur.x, y: t.y })
    points.push(elbow, t)
    horizontal = near(elbow.y, t.y)
  })
  return points
}

/** Port on a floating terminal for an orthogonal edge heading to `toward`: straight out if `toward` is level with the shape, else the facing side. */
function orthogonalPortToward(frame: Frame, toward: Pt): Port {
  const b = frame.bounds
  if (toward.y >= b.y && toward.y <= b.y + b.h && (toward.x < b.x || toward.x > b.x + b.w)) {
    const dir = { x: toward.x > frame.center.x ? 1 : -1, y: 0 }
    return { pt: projectOnAxis(frame, { x: frame.center.x, y: toward.y }, dir), dir }
  }
  if (toward.x >= b.x && toward.x <= b.x + b.w && (toward.y < b.y || toward.y > b.y + b.h)) {
    const dir = { x: 0, y: toward.y > frame.center.y ? 1 : -1 }
    return { pt: projectOnAxis(frame, { x: toward.x, y: frame.center.y }, dir), dir }
  }
  return sidePort(frame, facingSides(b, { x: toward.x, y: toward.y, w: 0, h: 0 })[0])
}

function simplify(points: Pt[]): Pt[] {
  const out: Pt[] = []
  for (const p of points) {
    const last = out[out.length - 1]
    if (last !== undefined && near(last.x, p.x) && near(last.y, p.y)) continue
    out.push(p)
    while (out.length >= 3) {
      const a = out[out.length - 3] as Pt
      const b = out[out.length - 2] as Pt
      const c = out[out.length - 1] as Pt
      const cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
      const dot = (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y)
      if (Math.abs(cross) > 1e-6 || dot < 0) break
      out.splice(out.length - 2, 1)
    }
  }
  return out
}

interface MarkerResult { svg: string; trim: number; extent: number }

/**
 * Arrowhead at `tip`, pointing away from `from`. Geometry follows mxGraph's
 * marker definitions: length size + stroke width (+1 for ER markers),
 * half-width length / widthFactor. `trim` is how far the line must stop short
 * of the tip so it does not show through the head.
 */
function marker(kind: string, tip: Pt, from: Pt, size: number, sw: number, filled: boolean, stroke: string): MarkerResult | null {
  const len = Math.hypot(tip.x - from.x, tip.y - from.y)
  if (len < 1e-9) return null
  const u = { x: (tip.x - from.x) / len, y: (tip.y - from.y) / len }
  const n = { x: -u.y, y: u.x }
  const at = (base: Pt, back: number, side: number): Pt => ({ x: base.x - u.x * back + n.x * side, y: base.y - u.y * back + n.y * side })
  const strokeAttrs = ` stroke="${esc(stroke)}" stroke-width="${fmt(sw)}"`
  const fill = filled ? esc(stroke) : 'none'
  switch (kind) {
    case 'classic':
    case 'classicThin':
    case 'block':
    case 'blockThin': {
      const wf = kind.endsWith('Thin') ? 3 : 2
      const l = size + sw
      const shift = sw * 1.118
      const t = at(tip, shift, 0)
      const notch = kind.startsWith('classic') ? ` L ${fmtPt(at(t, (l * 3) / 4, 0))}` : ''
      const d = `M ${fmtPt(t)} L ${fmtPt(at(t, l, l / wf))}${notch} L ${fmtPt(at(t, l, -l / wf))} Z`
      return { svg: `<path d="${d}" fill="${fill}"${strokeAttrs}/>`, trim: shift + (kind.startsWith('classic') ? (l * 3) / 4 : l), extent: l + shift }
    }
    case 'open':
    case 'openThin': {
      const wf = kind === 'openThin' ? 3 : 2
      const l = size + sw
      const shift = sw * 1.118
      const t = at(tip, shift, 0)
      const d = `M ${fmtPt(at(t, l, l / wf))} L ${fmtPt(t)} L ${fmtPt(at(t, l, -l / wf))}`
      return { svg: `<path d="${d}" fill="none"${strokeAttrs}/>`, trim: shift, extent: l + shift }
    }
    case 'oval': {
      const c = at(tip, size / 2, 0)
      return { svg: `<circle cx="${fmt(c.x)}" cy="${fmt(c.y)}" r="${fmt(size / 2)}" fill="${fill}"${strokeAttrs}/>`, trim: size, extent: size }
    }
    case 'diamond':
    case 'diamondThin': {
      const tw = kind === 'diamondThin' ? 3.4 : 2
      const l = size + sw
      const shift = sw * (kind === 'diamondThin' ? 0.9862 : 0.7071)
      const t = at(tip, shift, 0)
      const d = `M ${fmtPt(t)} L ${fmtPt(at(t, l / 2, l / tw))} L ${fmtPt(at(t, l, 0))} L ${fmtPt(at(t, l / 2, -l / tw))} Z`
      return { svg: `<path d="${d}" fill="${fill}"${strokeAttrs}/>`, trim: shift + l, extent: l + shift }
    }
    default: {
      const l = size + sw + 1
      const bar = (back: number): string => `M ${fmtPt(at(tip, back, l / 2))} L ${fmtPt(at(tip, back, -l / 2))}`
      const foot = `M ${fmtPt(at(tip, 0, l / 2))} L ${fmtPt(at(tip, l, 0))} L ${fmtPt(at(tip, 0, -l / 2))}`
      const circle = (back: number): string => {
        const c = at(tip, back, 0)
        return `<circle cx="${fmt(c.x)}" cy="${fmt(c.y)}" r="${fmt(size / 2)}" fill="#ffffff"${strokeAttrs}/>`
      }
      const path = (d: string): string => `<path d="${d}" fill="none"${strokeAttrs}/>`
      switch (kind) {
        case 'ERone': return { svg: path(bar(l / 2)), trim: 0, extent: l }
        case 'ERmandOne': return { svg: path(`${bar(l / 2)} ${bar(l)}`), trim: 0, extent: l }
        case 'ERmany': return { svg: path(foot), trim: 0, extent: l }
        case 'ERoneToMany': return { svg: path(`${foot} ${bar(l * 1.5)}`), trim: 0, extent: l * 1.5 }
        case 'ERzeroToOne': return { svg: path(bar(l / 2)) + circle(l * 1.5), trim: 0, extent: l * 1.5 + size / 2 }
        case 'ERzeroToMany': return { svg: path(foot) + circle(l * 1.5), trim: 0, extent: l * 1.5 + size / 2 }
        default: return null
      }
    }
  }
}

/** Shorten the polyline by `start` px at its first point and `end` px at its last. */
function trimPolyline(points: Pt[], start: number, end: number): Pt[] {
  const out = points.map(p => ({ ...p }))
  const shorten = (index: number, neighbour: number, amount: number): void => {
    const p = out[index] as Pt
    const q = out[neighbour] as Pt
    const len = Math.hypot(p.x - q.x, p.y - q.y)
    if (amount <= 0 || len < 1e-9) return
    const t = Math.min(amount, len - 0.5) / len
    if (t <= 0) return
    out[index] = { x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t }
  }
  if (out.length >= 2) {
    shorten(0, 1, start)
    shorten(out.length - 1, out.length - 2, end)
  }
  return out
}

function edgePath(points: Pt[], style: Style): string {
  const first = points[0] as Pt
  if (points.length > 2 && style.curved === '1') {
    let d = `M ${fmtPt(first)}`
    for (let i = 1; i < points.length - 2; i += 1) {
      const p = points[i] as Pt
      const q = points[i + 1] as Pt
      d += ` Q ${fmtPt(p)} ${fmtPt({ x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 })}`
    }
    return `${d} Q ${fmtPt(points[points.length - 2] as Pt)} ${fmtPt(points[points.length - 1] as Pt)}`
  }
  if (points.length > 2 && style.rounded === '1') {
    const r = num(style.arcSize, 20) / 2
    let d = `M ${fmtPt(first)}`
    for (let i = 1; i < points.length - 1; i += 1) {
      const prev = points[i - 1] as Pt
      const cur = points[i] as Pt
      const next = points[i + 1] as Pt
      const cut = (p: Pt): Pt => {
        const len = Math.hypot(p.x - cur.x, p.y - cur.y)
        const t = len === 0 ? 0 : Math.min(r, len / 2) / len
        return { x: cur.x + (p.x - cur.x) * t, y: cur.y + (p.y - cur.y) * t }
      }
      d += ` L ${fmtPt(cut(prev))} Q ${fmtPt(cur)} ${fmtPt(cut(next))}`
    }
    return `${d} L ${fmtPt(points[points.length - 1] as Pt)}`
  }
  return `M ${points.map(fmtPt).join(' L ')}`
}

/** Point at `fraction` of the polyline's length, moved `normal` px perpendicular to the segment it falls on. */
function pointAlong(points: Pt[], fraction: number, normal: number): Pt {
  const lengths = points.slice(1).map((p, i) => Math.hypot(p.x - (points[i] as Pt).x, p.y - (points[i] as Pt).y))
  const total = lengths.reduce((a, b) => a + b, 0)
  let remaining = Math.max(0, Math.min(1, fraction)) * total
  for (let i = 0; i < lengths.length; i += 1) {
    const len = lengths[i] as number
    if (remaining <= len || i === lengths.length - 1) {
      const a = points[i] as Pt
      const b = points[i + 1] as Pt
      const t = len === 0 ? 0 : Math.min(1, remaining / len)
      const ux = len === 0 ? 0 : (b.x - a.x) / len
      const uy = len === 0 ? 0 : (b.y - a.y) / len
      return { x: a.x + (b.x - a.x) * t - uy * normal, y: a.y + (b.y - a.y) * t + ux * normal }
    }
    remaining -= len
  }
  return points[0] ?? { x: 0, y: 0 }
}

function renderEdgeLabel(ctx: Context, label: string, style: Style, geometry: Geometry | null, points: Pt[], note: Note): void {
  const fraction = geometry !== null && geometry.relative ? (geometry.x + 1) / 2 : 0.5
  const normal = geometry !== null && geometry.relative ? geometry.y : 0
  const at = pointAlong(points, fraction, normal)
  const p = { x: at.x + (geometry?.offset?.x ?? 0), y: at.y + (geometry?.offset?.y ?? 0) }
  const base = fontFromStyle(style, note)
  const { lines, html } = parseLabel(label, style, base, note)
  renderText(ctx, {
    lines,
    base,
    box: { x: p.x, y: p.y, w: 0, h: 0 },
    align: enumValue<HAlign>(style, 'align', H_ALIGNS, 'center', note),
    valign: enumValue<VAlign>(style, 'verticalAlign', V_ALIGNS, 'middle', note),
    wrap: false,
    transform: IDENTITY,
    background: optionalColor(style.labelBackgroundColor, '#ffffff', 'labelBackgroundColor', note),
    border: optionalColor(style.labelBorderColor, '#000000', 'labelBorderColor', note),
    opacity: num(style.textOpacity, 100),
    preserveSpace: !html,
  })
}

interface Terminal { frame: Frame | null; point: Pt | null }

/**
 * Resolve an edge end: the terminal cell's frame (redirected to its outermost
 * collapsed ancestor), else the geometry's loose point. `hidden` means the
 * terminal is invisible, so the edge is not drawn.
 */
function resolveTerminal(ctx: Context, id: string | null, loose: Pt | null, cells: Map<string, Cell>, note: Note): Terminal | 'hidden' {
  if (id === null) return { frame: null, point: loose }
  let cell = cells.get(id)
  if (cell === undefined) {
    note('approximated', 'edge:terminal', `terminal "${id}" does not exist`)
    return { frame: null, point: loose }
  }
  if (cell.edge) {
    note('unsupported', 'edge:edge-terminal', 'edges connected to other edges are not supported')
    return { frame: null, point: loose }
  }
  for (let a: Cell | null = cell; a !== null; a = a.parent) if (!a.visible) return 'hidden'
  for (let a: Cell | null = cell.parent; a !== null; a = a.parent) if (a.vertex && a.collapsed) cell = a
  const frame = ctx.frames.get(cell.id) ?? null
  return { frame, point: frame === null ? loose : null }
}

/**
 * Route and draw one edge, then its own label and any label cells.
 *
 * Steps: resolve both terminals; route by edgeStyle (straight through
 * waypoints, orthogonal, elbow or entity-relation); compute arrowheads at the
 * untrimmed ends; trim the line under the heads; draw path, heads, labels.
 */
function renderEdge(ctx: Context, cell: Cell, cells: Map<string, Cell>, boxes: Map<string, Box | null>): void {
  const note = ctx.note(cell.id)
  const style = cell.style
  const g = cell.geometry
  const origin = originOf(cell, boxes)
  const shift = (p: Pt): Pt => ({ x: p.x + origin.x, y: p.y + origin.y })
  const waypoints = (g?.points ?? []).map(shift)
  const src = resolveTerminal(ctx, cell.sourceId, g?.sourcePoint ? shift(g.sourcePoint) : null, cells, note)
  const tgt = resolveTerminal(ctx, cell.targetId, g?.targetPoint ? shift(g.targetPoint) : null, cells, note)
  if (src === 'hidden' || tgt === 'hidden') return
  if ((src.frame === null && src.point === null) || (tgt.frame === null && tgt.point === null)) {
    note('unsupported', 'edge:dangling', 'edge has no usable source or target; not drawn')
    return
  }
  if ((style.shape ?? 'connector') !== 'connector') {
    note('unsupported', `shape=${style.shape ?? ''}`, `edge shape "${style.shape ?? ''}" is not supported; drawn as a plain connector`)
  }

  const edgeStyle = style.edgeStyle === undefined || style.edgeStyle === '' ? 'none' : style.edgeStyle
  if (!EDGE_STYLE_SET.has(edgeStyle)) note('approximated', `edgeStyle=${edgeStyle}`, `edgeStyle "${edgeStyle}" is not supported; routed as a straight line`)
  const srcPort = src.frame === null ? null : constraintPort(src.frame, style, 'exit')
  const tgtPort = tgt.frame === null ? null : constraintPort(tgt.frame, style, 'entry')
  const fixedOf = (t: Terminal, port: Port | null): Pt | null => port?.pt ?? t.point
  const boxOf = (t: Terminal): Box => t.frame?.bounds ?? { x: t.point?.x ?? 0, y: t.point?.y ?? 0, w: 0, h: 0 }
  const centreOf = (t: Terminal): Pt => fixedOf(t, null) ?? t.frame?.center ?? { x: 0, y: 0 }
  const looseDir = (from: Pt, to: Pt): Pt => snapDir({ x: to.x - from.x, y: to.y - from.y })

  let points: Pt[]
  if (src.frame !== null && src.frame === tgt.frame && waypoints.length === 0) {
    note('approximated', 'edge:loop', 'self-loop drawn as a fixed loop on the right side')
    const b = src.frame.bounds
    const c = src.frame.center
    const x = b.x + b.w
    points = [{ x, y: c.y - b.h / 4 }, { x: x + 20, y: c.y - b.h / 4 }, { x: x + 20, y: c.y + b.h / 4 }, { x, y: c.y + b.h / 4 }]
  } else if (edgeStyle === 'orthogonalEdgeStyle' || edgeStyle === 'elbowEdgeStyle' || edgeStyle === 'entityRelationEdgeStyle') {
    const axis = edgeStyle === 'entityRelationEdgeStyle' || (edgeStyle === 'elbowEdgeStyle' && style.elbow !== 'vertical')
      ? 'horizontal'
      : edgeStyle === 'elbowEdgeStyle' ? 'vertical' : 'auto'
    const [srcSide, tgtSide] = facingSides(boxOf(src), boxOf(tgt), axis)
    const portFor = (t: Terminal, fixed: Port | null, side: Side, toward: Pt | undefined, other: Terminal): Port => {
      if (fixed !== null) return fixed
      if (t.frame !== null) return toward !== undefined && edgeStyle === 'orthogonalEdgeStyle' ? orthogonalPortToward(t.frame, toward) : sidePort(t.frame, side)
      const p = t.point ?? { x: 0, y: 0 }
      return { pt: p, dir: axis === 'auto' ? looseDir(p, toward ?? centreOf(other)) : SIDE_DIR[side] }
    }
    const p0 = portFor(src, srcPort, srcSide, waypoints[0], tgt)
    const p1 = portFor(tgt, tgtPort, tgtSide, waypoints[waypoints.length - 1], src)
    if (edgeStyle === 'entityRelationEdgeStyle') {
      if (waypoints.length > 0) note('approximated', 'edge:waypoints', 'waypoints are ignored by entityRelationEdgeStyle')
      const seg = num(style.segment, 30)
      points = [p0.pt, { x: p0.pt.x + p0.dir.x * seg, y: p0.pt.y + p0.dir.y * seg }, { x: p1.pt.x + p1.dir.x * seg, y: p1.pt.y + p1.dir.y * seg }, p1.pt]
    } else if (edgeStyle === 'elbowEdgeStyle' && waypoints[0] !== undefined) {
      const w = waypoints[0]
      points = axis === 'horizontal'
        ? [p0.pt, { x: w.x, y: p0.pt.y }, { x: w.x, y: p1.pt.y }, p1.pt]
        : [p0.pt, { x: p0.pt.x, y: w.y }, { x: p1.pt.x, y: w.y }, p1.pt]
    } else if (waypoints.length > 0) {
      points = orthogonalThrough(p0, waypoints, p1)
    } else {
      points = orthogonalRoute(p0.pt, p0.dir, p1.pt, p1.dir, 20)
    }
  } else {
    const towardFromSource = waypoints[0] ?? fixedOf(tgt, tgtPort) ?? centreOf(tgt)
    const towardFromTarget = waypoints[waypoints.length - 1] ?? fixedOf(src, srcPort) ?? centreOf(src)
    const p0 = fixedOf(src, srcPort) ?? perimeterPoint(src.frame as Frame, towardFromSource)
    const p1 = fixedOf(tgt, tgtPort) ?? perimeterPoint(tgt.frame as Frame, towardFromTarget)
    points = [p0, ...waypoints, p1]
  }
  points = simplify(points)
  if (points.length < 2) return

  const stroke = resolveColor(style.strokeColor, '#000000', 'strokeColor', note)
  const sw = Math.max(0, num(style.strokeWidth, 1))
  const heads: string[] = []
  const trims = [0, 0]
  const ends: Array<['start' | 'end', Pt, Pt]> = [
    ['start', points[0] as Pt, points[1] as Pt],
    ['end', points[points.length - 1] as Pt, points[points.length - 2] as Pt],
  ]
  for (const [which, tip, from] of ends) {
    const kind = style[`${which}Arrow`] ?? (which === 'end' ? 'classic' : 'none')
    if (kind === 'none' || kind === '') continue
    if (!ARROW_SET.has(kind)) {
      note('unsupported', `${which}Arrow=${kind}`, `arrowhead "${kind}" is not supported; omitted`)
      continue
    }
    const size = Math.max(0, num(style[`${which}Size`], 6))
    const head = marker(kind, tip, from, size, sw, style[`${which}Fill`] !== '0', stroke)
    if (head === null) continue
    heads.push(head.svg)
    trims[which === 'start' ? 0 : 1] = head.trim
    ctx.bounds.addBox({ x: tip.x - head.extent, y: tip.y - head.extent, w: head.extent * 2, h: head.extent * 2 })
  }
  const line = trimPolyline(points, trims[0] ?? 0, trims[1] ?? 0)
  const lineStyle = newStyle(style, { fillColor: 'none', gradientColor: 'none' })
  const p = paint(ctx, lineStyle, note, false)
  const opacity = num(style.opacity, 100)
  const opacityAttr = opacity < 100 ? ` opacity="${fmt(Math.max(0, opacity) / 100)}"` : ''
  ctx.body.push(`<g${opacityAttr}><path d="${edgePath(line, style)}"${p.attrs} stroke-linejoin="round"/>${heads.join('')}</g>`)
  for (const pt of points) ctx.bounds.add(pt)
  ctx.drawn += 1

  if (cell.label !== '' && style.noLabel !== '1') renderEdgeLabel(ctx, cell.label, style, g, points, note)
  for (const child of cell.children) {
    if (!child.vertex || !child.visible || child.label === '' || child.style.noLabel === '1') continue
    renderEdgeLabel(ctx, child.label, child.style, child.geometry, points, ctx.note(child.id))
  }
}

/* ================================================================== *
 * Page assembly
 * ================================================================== */

/**
 * Render one page. Pass 1 computes every vertex frame so edges can attach to
 * cells that appear later in the document. Pass 2 walks the cell tree depth
 * first in document order, drawing each cell before its children, which is
 * draw.io's z-order. Collapsed cells hide their children; invisible cells
 * hide their subtree.
 */
function renderPage(page: PageSource, options: RenderOptions, index: number): RenderedPage {
  const ctx = new Context(`${options.idPrefix ?? 'dio'}${index}`, options.fontFamily ?? 'Helvetica, Arial, sans-serif')
  const roots = buildCells(page.model, ctx.note(null), id => ctx.note(id))
  const cells = new Map<string, Cell>()
  const visit = (cell: Cell): void => {
    cells.set(cell.id, cell)
    cell.children.forEach(visit)
  }
  roots.forEach(visit)

  const boxes = new Map<string, Box | null>()
  for (const cell of cells.values()) {
    if (cell.vertex && !(cell.parent?.edge ?? false)) ctx.frames.set(cell.id, computeFrame(cell, boxes, ctx.note(cell.id)))
  }

  const draw = (cell: Cell): void => {
    if (!cell.visible) return
    if (cell.edge) {
      renderEdge(ctx, cell, cells, boxes)
      return
    }
    if (cell.vertex) {
      const frame = ctx.frames.get(cell.id)
      if (frame !== undefined && frame !== null) renderVertex(ctx, cell, frame, ctx.note(cell.id))
      if (cell.collapsed) return
    }
    cell.children.forEach(draw)
  }
  roots.forEach(draw)

  const padding = Math.max(0, options.padding ?? 10)
  const b = ctx.bounds.empty ? { x: 0, y: 0, w: 0, h: 0 } : { x: ctx.bounds.minX, y: ctx.bounds.minY, w: ctx.bounds.maxX - ctx.bounds.minX, h: ctx.bounds.maxY - ctx.bounds.minY }
  const x = Math.floor(b.x - padding)
  const y = Math.floor(b.y - padding)
  const width = Math.ceil(b.x + b.w + padding) - x
  const height = Math.ceil(b.y + b.h + padding) - y

  const parts = [`<svg xmlns="http://www.w3.org/2000/svg" version="1.1" width="${width}" height="${height}" viewBox="${x} ${y} ${width} ${height}">`]
  if (ctx.defs.length > 0) parts.push(`<defs>${ctx.defs.join('')}</defs>`)
  const background = resolveColor(page.model.attrs.background, 'none', 'background', ctx.note(null))
  if (options.background !== false && background !== 'none') {
    parts.push(`<rect x="${x}" y="${y}" width="${width}" height="${height}" fill="${esc(background)}"/>`)
  }
  parts.push(...ctx.body, '</svg>')

  ctx.diagnostics.sort((a, b) => (a.severity === b.severity ? 0 : a.severity === 'unsupported' ? -1 : 1))
  const fidelity: Fidelity = ctx.drawn === 0 ? 'none' : ctx.diagnostics.length === 0 ? 'full' : 'partial'
  return { name: page.name, id: page.id, svg: parts.join(''), width, height, fidelity, diagnostics: ctx.diagnostics }
}
