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
 * Derived from the dsh-drawio translate module. Shape, marker, connector and
 * line-jump drawing are ported from draw.io and mxGraph (Apache-2.0).
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
  'rectangle', 'ellipse', 'doubleEllipse', 'rhombus', 'triangle', 'hexagon', 'parallelogram', 'trapezoid',
  'step', 'card', 'note', 'folder', 'cube', 'tape', 'document', 'callout',
  'process', 'internalStorage', 'manualInput', 'dataStorage', 'delay', 'display', 'offPageConnector', 'loopLimit',
  'or', 'xor', 'sortShape', 'collate', 'orEllipse', 'sumEllipse', 'lineEllipse', 'tapeData',
  'cross', 'plus', 'corner', 'tee', 'crossbar', 'curlyBracket', 'singleArrow', 'doubleArrow',
  'cloud', 'actor', 'cylinder', 'cylinder3', 'datastore', 'message', 'line', 'swimlane',
  'table', 'tableRow', 'partialRectangle', 'image', 'umlActor', 'umlBoundary', 'umlEntity', 'umlControl',
  'umlDestroy', 'umlLifeline', 'umlFrame', 'lollipop', 'requiredInterface', 'providedRequiredInterface', 'module', 'component',
  'startState', 'endState',
]

/** Arrowhead names the renderer draws for `startArrow` / `endArrow`. */
export const SUPPORTED_ARROWS: readonly string[] = [
  'none', 'classic', 'classicThin', 'block', 'blockThin', 'open', 'openThin', 'oval',
  'diamond', 'diamondThin', 'doubleBlock', 'box', 'circle', 'circlePlus', 'halfCircle', 'dash',
  'baseDash', 'cross', 'async', 'openAsync', 'manyOptional', 'ERone', 'ERmandOne', 'ERmany',
  'ERoneToMany', 'ERzeroToOne', 'ERzeroToMany',
]

/** Values of `edgeStyle` the renderer routes. */
export const SUPPORTED_EDGE_STYLES: readonly string[] = [
  'none', 'orthogonalEdgeStyle', 'elbowEdgeStyle', 'entityRelationEdgeStyle',
]

/** Edge `shape` values the renderer draws: plain connectors, flexArrow bands and link double lines. */
export const SUPPORTED_EDGE_SHAPES: readonly string[] = ['connector', 'flexArrow', 'link']

/** `perimeter` values honoured exactly; a vertex without one uses its bounding rectangle, as in draw.io. */
export const SUPPORTED_PERIMETERS: readonly string[] = [
  'rectanglePerimeter', 'ellipsePerimeter', 'rhombusPerimeter', 'trianglePerimeter', 'hexagonPerimeter2',
  'parallelogramPerimeter', 'trapezoidPerimeter', 'stepPerimeter', 'calloutPerimeter', 'centerPerimeter',
]

/** HTML tags honoured in `html=1` labels. Other tags are dropped (their text is kept). */
export const SUPPORTED_HTML_TAGS: readonly string[] = [
  'b', 'strong', 'i', 'em', 'u', 'ins', 's', 'strike', 'del', 'font',
  'span', 'a', 'code', 'tt', 'br', 'div', 'p', 'hr', 'ul', 'ol',
  'li', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
]

/** CSS properties honoured in `style` attributes inside HTML labels. */
export const SUPPORTED_CSS_PROPERTIES: readonly string[] = [
  'color', 'font-size', 'font-weight', 'font-style', 'font-family', 'text-decoration', 'text-decoration-line',
  'text-align', 'margin', 'margin-top', 'margin-bottom', 'margin-left', 'padding-left',
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
  shape: 'rectangle', perimeter: 'rectanglePerimeter', fillColor: 'default', strokeColor: 'default',
  fontColor: 'default', fontSize: '12', fontFamily: 'Helvetica', align: 'center', verticalAlign: 'middle',
})

const DEFAULT_EDGE: Style = newStyle({
  shape: 'connector', endArrow: 'classic', rounded: '1', strokeColor: 'default', fontColor: 'default',
  fontSize: '11', fontFamily: 'Helvetica', align: 'center', verticalAlign: 'middle', labelBackgroundColor: 'default',
})

const TEXT_STYLE: Style = { fillColor: 'none', gradientColor: 'none', strokeColor: 'none', align: 'left', verticalAlign: 'top' }

/** Named styles from draw.io's default stylesheet that the renderer honours. */
const NAMED_STYLES = new Map<string, Style>([
  ['text', TEXT_STYLE],
  ['edgeLabel', { ...TEXT_STYLE, labelBackgroundColor: 'default', fontSize: '11' }],
  ['ellipse', { shape: 'ellipse', perimeter: 'ellipsePerimeter' }],
  ['rhombus', { shape: 'rhombus', perimeter: 'rhombusPerimeter' }],
  ['triangle', { shape: 'triangle', perimeter: 'trianglePerimeter' }],
  ['swimlane', { shape: 'swimlane', fontSize: '12', fontStyle: '1', startSize: '23' }],
  ['group', { verticalAlign: 'top', fillColor: 'none', strokeColor: 'none', gradientColor: 'none', pointerEvents: '0' }],
  ['line', { shape: 'line', strokeWidth: '4', labelBackgroundColor: 'default', verticalAlign: 'top', spacingTop: '8' }],
  ['image', { shape: 'image', labelBackgroundColor: 'default', verticalAlign: 'top', verticalLabelPosition: 'bottom' }],
])

const RENDERED_KEYS = new Set([
  'shape', 'perimeter', 'rounded', 'arcSize', 'absoluteArcSize', 'fillColor', 'gradientColor', 'gradientDirection',
  'strokeColor', 'strokeWidth', 'dashed', 'dashPattern', 'fixDash', 'opacity', 'fillOpacity', 'strokeOpacity',
  'textOpacity', 'rotation', 'direction', 'flipH', 'flipV', 'size', 'fixedSize', 'margin', 'startSize',
  'horizontal', 'swimlaneFillColor', 'swimlaneLine', 'swimlaneHead', 'swimlaneBody', 'fontColor', 'fontSize',
  'fontFamily', 'fontStyle', 'align', 'verticalAlign', 'labelPosition', 'verticalLabelPosition', 'spacing',
  'spacingTop', 'spacingBottom', 'spacingLeft', 'spacingRight', 'labelBackgroundColor', 'labelBorderColor',
  'whiteSpace', 'html', 'noLabel', 'overflow', 'boundedLbl', 'shadow', 'shadowColor', 'shadowOffsetX',
  'shadowOffsetY', 'shadowBlur', 'shadowOpacity', 'edgeStyle', 'elbow', 'curved', 'endArrow', 'startArrow',
  'endSize', 'endFill', 'startFill', 'startFillColor', 'endFillColor', 'startStrokeColor', 'endStrokeColor',
  'exitX', 'exitY', 'exitDx', 'exitDy', 'exitPerimeter', 'entryX', 'entryY', 'entryDx', 'entryDy',
  'entryPerimeter', 'segment', 'jumpStyle', 'jumpSize', 'noJump', 'perimeterSpacing', 'sourcePerimeterSpacing',
  'targetPerimeterSpacing', 'width', 'height', 'startWidth', 'endWidth', 'image', 'imageAspect',
  'imageBackground', 'imageBorder', 'top', 'left', 'bottom', 'right', 'rowLines', 'columnLines', 'tabWidth',
  'tabHeight', 'tabPosition', 'folderSymbol', 'darkOpacity', 'darkOpacity2', 'position', 'position2', 'base',
  'arrowWidth', 'arrowSize', 'dx', 'dy', 'jettyWidth', 'jettyHeight', 'inset', 'lid', 'participant',
  'lifelineDashed', 'lifelineColor', 'line',
])

/** Keys that only affect editing behaviour or automatic layout, so a static rendering ignores them. */
const INERT_KEYS = new Set([
  'resizable', 'movable', 'rotatable', 'deletable', 'editable', 'cloneable', 'bendable', 'connectable',
  'locked', 'autosize', 'points', 'pointerEvents', 'container', 'collapsible', 'recursiveResize', 'expand',
  'childLayout', 'resizeParent', 'resizeParentMax', 'resizeLast', 'horizontalStack', 'stackLayout',
  'marginTop', 'marginBottom', 'marginLeft', 'marginRight', 'stackFill', 'stackSpacing', 'treeFolding',
  'treeMoving', 'metaEdit', 'allowArrows', 'snapToPoint', 'part', 'portConstraint', 'sourcePortConstraint',
  'targetPortConstraint', 'portConstraintRotation', 'aspect', 'backgroundOutline', 'jettySize',
  'sourceJettySize', 'targetJettySize', 'orthogonalLoop', 'orthogonal', 'textDirection', 'outlineConnect',
  'dropTarget', 'fixedRows', 'jumpLayers',
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

const COLOR_DEFAULTS = new Map([['fillColor', '#ffffff'], ['strokeColor', '#000000'], ['fontColor', '#000000']])

/**
 * Resolve a colour key of a cell, following draw.io's references:
 * `inherit` takes the parent's value of the same key, `parentFillColor` /
 * `parentStrokeColor` the parent's fill or stroke, and the values
 * `fillColor` / `strokeColor` the cell's own fill or stroke.
 */
function cellColor(cell: Cell, key: string, fallback: string, note: Note, optional = false, depth = 0): string {
  const value = cell.style[key]?.trim()
  if (depth > 32) return 'none'
  if (value === 'inherit' || value === 'parentFillColor' || value === 'parentStrokeColor') {
    const parentKey = value === 'parentFillColor' ? 'fillColor' : value === 'parentStrokeColor' ? 'strokeColor' : key
    const parent = cell.parent
    if (parent === null || !(parent.vertex || parent.edge)) return 'none'
    return cellColor(parent, parentKey, COLOR_DEFAULTS.get(parentKey) ?? fallback, note, optional, depth + 1)
  }
  if ((value === 'fillColor' || value === 'strokeColor') && value !== key) {
    return cellColor(cell, value, COLOR_DEFAULTS.get(value) ?? fallback, note, false, depth + 1)
  }
  return optional ? optionalColor(value, fallback, key, note) : resolveColor(value, fallback, key, note)
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

/** One rendered line of a label. */
interface Line {
  runs: Run[]
  align: HAlign | null
  /** Left indent in px from lists, blockquotes and margin-left. */
  indent: number
  /** List marker drawn left of the indent, e.g. `•` or `2.`. */
  marker: string | null
  /** Space above the line in px: collapsed block margins. */
  spaceBefore: number
  /** A horizontal rule (`<hr>`) instead of text. */
  rule: boolean
}

interface ParsedLabel { lines: Line[]; spaceAfter: number }

const blankLine = (): Line => ({ runs: [], align: null, indent: 0, marker: null, spaceBefore: 0, rule: false })

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
/** Browser default vertical margins of block elements, in em of the element's font size. */
const BLOCK_MARGINS = new Map([
  ['p', 1], ['ul', 1], ['ol', 1], ['blockquote', 1], ['h1', 0.67], ['h2', 0.83], ['h3', 1], ['h4', 1.33],
  ['h5', 1.67], ['h6', 2.33],
])
const HTML_FONT_SIZES = [10, 13, 16, 18, 24, 32, 48]
const TAG_PATTERN = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:\s+[^\s=>/]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>"']+))?)*)\s*(\/?)>/y
const ATTR_PATTERN = /([^\s=>/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+)))?/g

const sameFont = (a: FontState, b: FontState): boolean =>
  a.bold === b.bold && a.italic === b.italic && a.underline === b.underline && a.strike === b.strike
  && a.color === b.color && a.size === b.size && a.family === b.family

function parseCssSize(value: string, current: number): number | null {
  const m = /^(-?[0-9.]+)\s*(px|pt|em|rem|%)?$/i.exec(value.trim())
  if (m === null) return value.trim() === 'auto' ? 0 : null
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

/** Block box properties collected from CSS; null means "browser default". */
interface BlockBox { top: number | null; bottom: number | null; left: number | null; padLeft: number | null }

function applyCss<T extends FontState & { align: HAlign | null }>(state: T, css: string, box: BlockBox, note: Note): T {
  const next = { ...state }
  for (const declaration of css.split(';')) {
    const colon = declaration.indexOf(':')
    if (colon === -1) continue
    const prop = declaration.slice(0, colon).trim().toLowerCase()
    const value = declaration.slice(colon + 1).replace(/!important/i, '').trim()
    const length = (): number | null => parseCssSize(value, next.size)
    switch (prop) {
      case 'color':
        if (PLAIN_COLOR.test(value) || COLOR_FUNCTION.test(value)) next.color = value
        else note('approximated', 'css:color', `CSS colour "${value}" is not supported; ignored`)
        break
      case 'font-size': {
        const size = length()
        if (size !== null && size > 0) next.size = size
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
      case 'margin': {
        const parts = value.split(/\s+/).map(v => parseCssSize(v, next.size) ?? 0)
        box.top = parts[0] ?? 0
        box.bottom = parts[2] ?? parts[0] ?? 0
        box.left = parts[3] ?? parts[1] ?? parts[0] ?? 0
        break
      }
      case 'margin-top':
        box.top = length() ?? box.top
        break
      case 'margin-bottom':
        box.bottom = length() ?? box.bottom
        break
      case 'margin-left':
        box.left = length() ?? box.left
        break
      case 'padding-left':
        box.padLeft = length() ?? box.padLeft
        break
      case 'margin-right':
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
 * ends a line; block elements start and end lines without creating empty
 * ones and contribute browser-default margins, which collapse between
 * adjacent blocks; lists indent by 40 px and mark each item; inline elements
 * push a style frame that the matching end tag pops; unsupported tags are
 * reported and their text kept. Trailing empty lines are removed.
 */
function parseHtmlLabel(src: string, base: FontState, note: Note): ParsedLabel {
  type State = FontState & { align: HAlign | null; indent: number }
  const lines: Line[] = [blankLine()]
  const stack: Array<{ tag: string; saved: State; marginBottom: number }> = []
  const lists: Array<{ ordered: boolean; counter: number }> = []
  let state: State = { ...base, align: null, indent: 0 }
  let pending = 0
  let marker: string | null = null

  const current = (): Line => lines[lines.length - 1] as Line
  const hasContent = (line: Line): boolean => line.rule || line.runs.some(run => run.text !== '')
  const trimEnd = (line: Line): void => {
    for (let i = line.runs.length - 1; i >= 0; i -= 1) {
      const run = line.runs[i] as Run
      run.text = run.text.replace(/ +$/, '')
      if (run.text !== '') break
    }
    line.runs = line.runs.filter(run => run.text !== '')
  }
  const begin = (line: Line): void => {
    line.spaceBefore = pending
    line.indent = state.indent
    line.align = state.align
    line.marker = marker
    pending = 0
    marker = null
  }
  const newline = (): void => {
    const line = current()
    trimEnd(line)
    if (!hasContent(line)) begin(line)
    lines.push(blankLine())
  }
  const blockBreak = (): void => {
    if (hasContent(current())) newline()
  }
  const append = (raw: string): void => {
    let text = raw.replace(/[ \t\n\r\f]+/g, ' ')
    const line = current()
    const last = line.runs[line.runs.length - 1]
    if (!hasContent(line) || (last?.text.endsWith(' ') ?? false)) text = text.replace(/^ /, '')
    if (text === '') return
    if (!hasContent(line)) begin(line)
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
    const tag = (m[2] ?? '').toLowerCase()

    if (m[1] === '/') {
      let marginBottom = 0
      for (let k = stack.length - 1; k >= 0; k -= 1) {
        const frame = stack[k] as { tag: string; saved: State; marginBottom: number }
        if (frame.tag !== tag) continue
        state = frame.saved
        marginBottom = frame.marginBottom
        stack.length = k
        break
      }
      if (tag === 'ul' || tag === 'ol') lists.pop()
      if (BLOCK_TAGS.has(tag)) {
        blockBreak()
        pending = Math.max(pending, marginBottom)
      }
      continue
    }

    if (!SUPPORTED_TAG_SET.has(tag)) note('approximated', `html:<${tag}>`, `HTML <${tag}> in a label is not supported; its text is kept`)
    if (tag === 'br') {
      newline()
      continue
    }
    if (tag === 'hr') {
      blockBreak()
      const margin = state.size * 0.5
      pending = Math.max(pending, margin)
      const line = current()
      begin(line)
      line.rule = true
      lines.push(blankLine())
      pending = margin
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
    }
    const align = attrs.get('align')
    if (align !== undefined) next.align = parseAlign(align) ?? next.align
    const box: BlockBox = { top: null, bottom: null, left: null, padLeft: null }
    const css = attrs.get('style')
    if (css !== undefined) next = applyCss(next, css, box, note)
    if (tag === 'ul' || tag === 'ol') next.indent += box.padLeft ?? 40
    else if (tag === 'blockquote') next.indent += 40
    else if (box.padLeft !== null) next.indent += box.padLeft
    if (box.left !== null) next.indent += box.left

    if (BLOCK_TAGS.has(tag)) {
      const nested = (tag === 'ul' || tag === 'ol') && lists.length > 0
      const em = nested ? 0 : (BLOCK_MARGINS.get(tag) ?? 0) * next.size
      pending = Math.max(pending, box.top ?? em)
      stack.push({ tag, saved: state, marginBottom: box.bottom ?? em })
    } else {
      stack.push({ tag, saved: state, marginBottom: 0 })
    }
    state = next
    if (tag === 'ul' || tag === 'ol') lists.push({ ordered: tag === 'ol', counter: 1 })
    if (tag === 'li') {
      const list = lists[lists.length - 1]
      if (list?.ordered ?? false) {
        marker = `${list?.counter ?? 1}.`
        if (list !== undefined) list.counter += 1
      } else marker = '•'
    }
  }
  trimEnd(current())
  while (lines.length > 0 && !hasContent(lines[lines.length - 1] as Line)) lines.pop()
  return { lines, spaceAfter: lines.length > 0 ? pending : 0 }
}

function parsePlainLabel(src: string, base: FontState): ParsedLabel {
  return { lines: src.split('\n').map(text => ({ ...blankLine(), runs: [{ ...base, text }] })), spaceAfter: 0 }
}

/**
 * Greedy word wrap within the width left after the line's indent. Break
 * opportunities are spaces and positions between CJK characters; a word wider
 * than the line is split by character.
 */
function wrapLine(line: Line, maxWidth: number): Line[] {
  if (line.rule) return [line]
  const available = Math.max(1, maxWidth - line.indent)
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
    if (width + piece.width > available && row.some(p => !p.space)) {
      trimRow(row)
      row = []
      rows.push(row)
      width = 0
    }
    if (piece.width > available && row.length === 0) {
      let chunk = ''
      let chunkWidth = 0
      for (const ch of piece.text) {
        const w = textWidth(ch, piece.run)
        if (chunkWidth + w > available && chunk !== '') {
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
  return rows.map((row, index) => {
    const runs: Run[] = []
    for (const piece of row) {
      const last = runs[runs.length - 1]
      if (last !== undefined && sameFont(last, piece.run)) last.text += piece.text
      else runs.push({ ...piece.run, text: piece.text })
    }
    return {
      runs,
      align: line.align,
      indent: line.indent,
      marker: index === 0 ? line.marker : null,
      spaceBefore: index === 0 ? line.spaceBefore : 0,
      rule: false,
    }
  })
}

/* ================================================================== *
 * Render context
 * ================================================================== */

interface Frame {
  style: Style
  box: Box
  center: Pt
  /** Rotation and flips about the centre: maps cell-box coordinates to the page. */
  cellMat: Mat
  /** cellMat plus `direction`: maps shape-box coordinates to the page. */
  shapeMat: Mat
  shapeBox: Box
  kind: string
  /** Perimeter polygon in page coordinates, from the cell's `perimeter` style. */
  outline: Pt[]
  bounds: Box
  /** `centerPerimeter`: edges end at the centre. */
  centerOnly: boolean
}

/** A drawn edge's route, kept so later edges can jump over it. */
interface EdgeLine { pts: Pt[]; bounds: Box; jumpable: boolean }

class Context {
  readonly diagnostics: Diagnostic[] = []
  readonly defs: string[] = []
  readonly body: string[] = []
  readonly bounds = new Bounds()
  readonly frames = new Map<string, Frame | null>()
  readonly edgeLines: EdgeLine[] = []
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

  /**
   * Filter attribute for draw.io's drop shadow (offset 2,3 px, blur 2 px,
   * #808080 unless styled), or '' when `shadow` is off. The filter region
   * is set in user space from `region` so zero-height lines keep their shadow.
   */
  shadow(style: Style, region: Box, note: Note): string {
    if (style.shadow !== '1') return ''
    const dx = num(style.shadowOffsetX, 2)
    const dy = num(style.shadowOffsetY, 3)
    const blur = Math.max(0, num(style.shadowBlur, 2))
    const color = resolveColor(style.shadowColor, '#808080', 'shadowColor', note)
    const opacity = clamp(num(style.shadowOpacity, 100), 0, 100) / 100
    const pad = Math.abs(dx) + Math.abs(dy) + blur * 3 + 4
    const id = this.newId('s')
    this.defs.push(`<filter id="${esc(id)}" filterUnits="userSpaceOnUse" x="${fmt(region.x - pad)}" y="${fmt(region.y - pad)}" width="${fmt(region.w + 2 * pad)}" height="${fmt(region.h + 2 * pad)}"><feDropShadow dx="${fmt(dx)}" dy="${fmt(dy)}" stdDeviation="${fmt(blur / 2)}" flood-color="${esc(color)}" flood-opacity="${fmt(opacity)}"/></filter>`)
    this.bounds.addBox({ x: region.x + Math.min(0, dx) - blur, y: region.y + Math.min(0, dy) - blur, w: region.w + Math.abs(dx) + 2 * blur, h: region.h + Math.abs(dy) + 2 * blur })
    return ` filter="url(#${id})"`
  }

  clip(box: Box): string {
    const id = this.newId('c')
    this.defs.push(`<clipPath id="${esc(id)}"><rect x="${fmt(box.x)}" y="${fmt(box.y)}" width="${fmt(Math.max(0, box.w))}" height="${fmt(Math.max(0, box.h))}"/></clipPath>`)
    return id
  }

  gradient(from: string, to: string, direction: string | undefined): string {
    const id = this.newId('g')
    const [x1, y1, x2, y2] = direction === 'north' ? [0, 1, 0, 0] : direction === 'east' ? [0, 0, 1, 0] : direction === 'west' ? [1, 0, 0, 0] : [0, 0, 0, 1]
    this.defs.push(`<linearGradient id="${esc(id)}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"><stop offset="0" stop-color="${esc(from)}"/><stop offset="1" stop-color="${esc(to)}"/></linearGradient>`)
    return `url(#${id})`
  }
}

/* ================================================================== *
 * Text rendering
 * ================================================================== */

interface TextBlock {
  lines: Line[]
  spaceAfter: number
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
  /** draw.io `overflow`: visible, hidden (clip to the box), fill (clip, background fills the box) or width. */
  overflow: string
}

function fontFromStyle(style: Style, color: string): FontState {
  const flags = num(style.fontStyle, 0)
  return {
    bold: (flags & 1) !== 0,
    italic: (flags & 2) !== 0,
    underline: (flags & 4) !== 0,
    strike: (flags & 8) !== 0,
    color,
    size: Math.max(1, num(style.fontSize, 12)),
    family: style.fontFamily ?? 'Helvetica',
  }
}

/**
 * Emit a text block: one `<text>` per line inside a group carrying the base
 * font, with `<tspan>`s only where a run differs from the base. Lines are
 * 1.2 em tall plus their collapsed block margins; each baseline sits so
 * capitals centre on the line box. List markers hang left of the indent.
 */
function renderText(ctx: Context, block: TextBlock): void {
  const { box, base } = block
  const lines = block.wrap && box.w > 0 ? block.lines.flatMap(line => wrapLine(line, box.w)) : block.lines
  if (lines.length === 0) return
  const metrics = lines.map(line => {
    const size = lineSize(line, base.size)
    return { size, width: line.rule ? line.indent : lineWidth(line) + line.indent, height: line.rule ? 2 : size * 1.2 }
  })
  const height = metrics.reduce((sum, m, index) => sum + m.height + (lines[index]?.spaceBefore ?? 0), 0) + block.spaceAfter
  const blockWidth = block.wrap && box.w > 0 ? box.w : Math.max(...metrics.map(m => m.width))
  const top = block.valign === 'top' ? box.y : block.valign === 'bottom' ? box.y + box.h - height : box.y + (box.h - height) / 2
  const left = block.align === 'left' ? box.x : block.align === 'right' ? box.x + box.w - blockWidth : box.x + (box.w - blockWidth) / 2

  const parts: string[] = []
  const frame = block.overflow === 'fill' ? box
    : block.overflow === 'width' ? { x: box.x, y: top, w: box.w, h: height }
      : { x: left - 2, y: top, w: blockWidth + 4, h: height }
  if (block.background !== 'none' || block.border !== 'none') {
    parts.push(`<rect x="${fmt(frame.x)}" y="${fmt(frame.y)}" width="${fmt(frame.w)}" height="${fmt(frame.h)}" fill="${esc(block.background)}" stroke="${esc(block.border)}"/>`)
  }
  let y = top
  lines.forEach((line, index) => {
    const m = metrics[index] ?? { size: base.size, width: 0, height: base.size * 1.2 }
    y += line.spaceBefore
    if (line.rule) {
      parts.push(`<path d="M ${fmt(left + line.indent)} ${fmt(y + 1)} H ${fmt(left + blockWidth)}" fill="none" stroke="${esc(base.color)}" stroke-width="1"/>`)
    } else if (line.runs.some(run => run.text !== '')) {
      const align = line.align ?? block.align
      const x0 = left + line.indent
      const w0 = blockWidth - line.indent
      const x = align === 'left' ? x0 : align === 'right' ? x0 + w0 : x0 + w0 / 2
      const anchor = align === 'left' ? 'start' : align === 'right' ? 'end' : 'middle'
      const baseline = y + m.height / 2 + m.size * 0.36
      if (line.marker !== null) {
        parts.push(`<text x="${fmt(x0 - m.size * 0.4)}" y="${fmt(baseline)}" text-anchor="end">${esc(line.marker)}</text>`)
      }
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
      parts.push(`<text x="${fmt(x)}" y="${fmt(baseline)}" text-anchor="${anchor}">${spans.join('')}</text>`)
    }
    y += m.height
  })

  let attrs = ` font-family="${esc(ctx.fontFamily(base.family))}" font-size="${fmt(base.size)}" fill="${esc(base.color)}"`
  if (base.bold) attrs += ' font-weight="bold"'
  if (base.italic) attrs += ' font-style="italic"'
  if (block.opacity < 100) attrs += ` opacity="${fmt(Math.max(0, block.opacity) / 100)}"`
  if (block.preserveSpace) attrs += ' xml:space="preserve"'
  const clipped = block.overflow === 'hidden' || block.overflow === 'fill'
  if (clipped) attrs += ` clip-path="url(#${ctx.clip(box)})"`
  ctx.body.push(`<g${attrs}${matAttr(block.transform)}>${parts.join('')}</g>`)
  ctx.bounds.addBox(clipped ? box : frame, block.transform)
}

const H_ALIGNS = new Set(['left', 'center', 'right'])
const V_ALIGNS = new Set(['top', 'middle', 'bottom'])
const OVERFLOWS = new Set(['visible', 'hidden', 'fill', 'width', 'block'])

function enumValue<T extends string>(style: Style, key: string, allowed: Set<string>, fallback: T, note: Note): T {
  const value = style[key]
  if (value === undefined || value === '') return fallback
  if (allowed.has(value)) return value as T
  note('approximated', `${key}=${value}`, `${key} "${value}" is not supported; using ${fallback}`)
  return fallback
}

function parseLabel(label: string, style: Style, base: FontState, note: Note): ParsedLabel & { html: boolean } {
  const html = style.html === '1'
  return { ...(html ? parseHtmlLabel(label, base, note) : parsePlainLabel(label, base)), html }
}

/* ================================================================== *
 * Canvas (port of mxGraph's canvas API)
 * ================================================================== */

interface CanvasState {
  dx: number
  dy: number
  fill: string
  stroke: string
  strokeWidth: number
  dashed: boolean
  dashPattern: string
  fixDash: boolean
  fillAlpha: number
  strokeAlpha: number
  lineCap: string
  lineJoin: string
  miterLimit: number
}

/**
 * Records paths in page coordinates and emits one SVG element per fill or
 * stroke call, so draw.io shape code ports line for line. Shadows are
 * applied by the caller to the whole shape.
 */
class Canvas {
  readonly parts: string[] = []
  private d = ''
  private state: CanvasState
  private readonly stack: CanvasState[] = []

  constructor(init: Partial<CanvasState>) {
    this.state = {
      dx: 0, dy: 0, fill: 'none', stroke: 'none', strokeWidth: 1, dashed: false, dashPattern: '3 3',
      fixDash: false, fillAlpha: 1, strokeAlpha: 1, lineCap: 'flat', lineJoin: 'miter', miterLimit: 10, ...init,
    }
  }

  save(): void { this.stack.push({ ...this.state }) }
  restore(): void { this.state = this.stack.pop() ?? this.state }
  translate(dx: number, dy: number): void {
    this.state.dx += dx
    this.state.dy += dy
  }
  setFillColor(color: string | null): void { this.state.fill = color ?? 'none' }
  setStrokeColor(color: string | null): void { this.state.stroke = color ?? 'none' }
  setStrokeWidth(width: number): void { this.state.strokeWidth = width }
  setDashed(dashed: boolean): void { this.state.dashed = dashed }
  setDashPattern(pattern: string, fixDash: boolean): void {
    this.state.dashPattern = pattern
    this.state.fixDash = fixDash
  }
  setFillAlpha(alpha: number): void { this.state.fillAlpha = alpha }
  setLineCap(cap: string): void { this.state.lineCap = cap }
  setLineJoin(join: string): void { this.state.lineJoin = join }
  setMiterLimit(limit: number): void { this.state.miterLimit = limit }

  begin(): void { this.d = '' }
  end(): void { }
  private p(x: number, y: number): string { return `${fmt(x + this.state.dx)} ${fmt(y + this.state.dy)}` }
  moveTo(x: number, y: number): void { this.d += ` M ${this.p(x, y)}` }
  lineTo(x: number, y: number): void { this.d += ` L ${this.p(x, y)}` }
  quadTo(x1: number, y1: number, x2: number, y2: number): void { this.d += ` Q ${this.p(x1, y1)} ${this.p(x2, y2)}` }
  curveTo(x1: number, y1: number, x2: number, y2: number, x3: number, y3: number): void {
    this.d += ` C ${this.p(x1, y1)} ${this.p(x2, y2)} ${this.p(x3, y3)}`
  }
  arcTo(rx: number, ry: number, angle: number, largeArc: number, sweep: number, x: number, y: number): void {
    this.d += ` A ${fmt(rx)} ${fmt(ry)} ${fmt(angle)} ${largeArc ? 1 : 0} ${sweep ? 1 : 0} ${this.p(x, y)}`
  }
  close(): void { this.d += ' Z' }
  rect(x: number, y: number, w: number, h: number): void {
    this.d = `M ${this.p(x, y)} L ${this.p(x + w, y)} L ${this.p(x + w, y + h)} L ${this.p(x, y + h)} Z`
  }
  roundrect(x: number, y: number, w: number, h: number, rx: number, ry: number): void {
    const r = Math.max(0, Math.min(rx, w / 2))
    const s = Math.max(0, Math.min(ry, h / 2))
    const a = `A ${fmt(r)} ${fmt(s)} 0 0 1`
    this.d = `M ${this.p(x + r, y)} L ${this.p(x + w - r, y)} ${a} ${this.p(x + w, y + s)} L ${this.p(x + w, y + h - s)} ${a} ${this.p(x + w - r, y + h)}`
      + ` L ${this.p(x + r, y + h)} ${a} ${this.p(x, y + h - s)} L ${this.p(x, y + s)} ${a} ${this.p(x + r, y)} Z`
  }
  ellipse(x: number, y: number, w: number, h: number): void {
    const a = `A ${fmt(w / 2)} ${fmt(h / 2)} 0 1 1`
    this.d = `M ${this.p(x, y + h / 2)} ${a} ${this.p(x + w, y + h / 2)} ${a} ${this.p(x, y + h / 2)} Z`
  }
  image(x: number, y: number, w: number, h: number, src: string, keepAspect: boolean): void {
    this.parts.push(`<image x="${fmt(x + this.state.dx)}" y="${fmt(y + this.state.dy)}" width="${fmt(w)}" height="${fmt(h)}" preserveAspectRatio="${keepAspect ? 'xMidYMid meet' : 'none'}" xlink:href="${esc(src)}"/>`)
  }
  raw(svg: string): void { this.parts.push(svg) }
  fill(): void { this.emit(true, false) }
  stroke(): void { this.emit(false, true) }
  fillAndStroke(): void { this.emit(true, true) }

  private emit(fill: boolean, stroke: boolean): void {
    const s = this.state
    const d = this.d.trim()
    this.d = ''
    const f = fill ? s.fill : 'none'
    const st = stroke && s.strokeWidth > 0 ? s.stroke : 'none'
    if (d === '' || (f === 'none' && st === 'none')) return
    let a = ` d="${d}" fill="${esc(f)}"`
    if (f !== 'none' && s.fillAlpha < 1) a += ` fill-opacity="${fmt(s.fillAlpha)}"`
    if (st === 'none') a += ' stroke="none"'
    else {
      a += ` stroke="${esc(st)}" stroke-width="${fmt(s.strokeWidth)}"`
      if (s.strokeAlpha < 1) a += ` stroke-opacity="${fmt(s.strokeAlpha)}"`
      if (s.dashed) {
        const scale = s.fixDash ? 1 : s.strokeWidth
        a += ` stroke-dasharray="${s.dashPattern.split(/\s+/).map(v => fmt(Number(v) * scale)).join(' ')}"`
      }
      if (s.lineCap !== 'flat') a += ` stroke-linecap="${s.lineCap}"`
      if (s.lineJoin === 'round' || s.lineJoin === 'bevel') a += ` stroke-linejoin="${s.lineJoin}"`
      if (s.miterLimit !== 10) a += ` stroke-miterlimit="${fmt(s.miterLimit)}"`
    }
    this.parts.push(`<path${a}/>`)
  }
}

/**
 * mxShape.addPoints: a polyline or polygon through `input`; with `rounded`,
 * each corner not listed in `exclude` is cut back by up to `arcSize` and
 * joined with a quadratic curve.
 */
function addPoints(c: Canvas, input: Pt[], rounded: boolean, arcSize: number, close: boolean, exclude: number[] | null = null, initialMove = true): void {
  if (input.length === 0) return
  let pts = input
  const pe = pts[pts.length - 1] as Pt
  if (close && rounded) {
    pts = pts.slice()
    const p0 = pts[0] as Pt
    pts.splice(0, 0, { x: pe.x + (p0.x - pe.x) / 2, y: pe.y + (p0.y - pe.y) / 2 })
  }
  const at = (index: number): Pt => pts[((index % pts.length) + pts.length) % pts.length] as Pt
  let pt = pts[0] as Pt
  let i = 1
  if (initialMove) c.moveTo(pt.x, pt.y)
  else c.lineTo(pt.x, pt.y)
  while (i < (close ? pts.length : pts.length - 1)) {
    let tmp = at(i)
    let dx = pt.x - tmp.x
    let dy = pt.y - tmp.y
    if (rounded && (dx !== 0 || dy !== 0) && (exclude === null || !exclude.includes(i - 1))) {
      let dist = Math.sqrt(dx * dx + dy * dy)
      c.lineTo(tmp.x + (dx * Math.min(arcSize, dist / 2)) / dist, tmp.y + (dy * Math.min(arcSize, dist / 2)) / dist)
      let next = at(i + 1)
      while (i < pts.length - 2 && Math.round(next.x - tmp.x) === 0 && Math.round(next.y - tmp.y) === 0) {
        next = at(i + 2)
        i += 1
      }
      dx = next.x - tmp.x
      dy = next.y - tmp.y
      dist = Math.max(1, Math.sqrt(dx * dx + dy * dy))
      const x2 = tmp.x + (dx * Math.min(arcSize, dist / 2)) / dist
      const y2 = tmp.y + (dy * Math.min(arcSize, dist / 2)) / dist
      c.quadTo(tmp.x, tmp.y, x2, y2)
      tmp = { x: x2, y: y2 }
    } else {
      c.lineTo(tmp.x, tmp.y)
    }
    pt = tmp
    i += 1
  }
  if (close) c.close()
  else c.lineTo(pe.x, pe.y)
}

/* ================================================================== *
 * Shapes (ported from draw.io's Shapes.js and mxGraph, Apache-2.0)
 * ================================================================== */

interface ShapeEnv {
  style: Style
  cell: Cell
  fill: string
  stroke: string
  laneFill: string
  sw: number
  rounded: boolean
  note: Note
}

/** Label insets as in mxShape.getLabelMargins: left, top, right and bottom distances. */
interface Margins { left: number; top: number; right: number; bottom: number }

type Paint = (c: Canvas, x: number, y: number, w: number, h: number, e: ShapeEnv) => void

interface ShapeDef {
  paint: Paint
  /** Label insets, applied with the shape's direction and flips. */
  margins?: (w: number, h: number, e: ShapeEnv) => Margins | null
  /** Replacement label box in cell-box coordinates. */
  labelBounds?: (rect: Box, e: ShapeEnv) => Box
}

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v))
const sv = (style: Style, key: string, fallback: number): number => num(style[key], fallback)
const lineArc = (style: Style): number => sv(style, 'arcSize', 20) / 2
const isFixed = (style: Style): boolean => style.fixedSize !== undefined && style.fixedSize !== '' && style.fixedSize !== '0'
const boundedLabel = (style: Style): boolean => style.boundedLbl === '1'
const margins = (left = 0, top = 0, right = 0, bottom = 0): Margins => ({ left, top, right, bottom })

function rectArc(style: Style, w: number, h: number): number {
  if (style.absoluteArcSize === '1') return Math.min(w / 2, h / 2, sv(style, 'arcSize', 20) / 2)
  const f = sv(style, 'arcSize', 15) / 100
  return Math.min(w * f, h * f)
}

const hexagonInset = (s: Style, w: number): number => (isFixed(s) ? clamp(sv(s, 'size', 20), 0, w * 0.5) : w * clamp(sv(s, 'size', 0.25), 0, 1))
const parallelogramInset = (s: Style, w: number): number => (isFixed(s) ? clamp(sv(s, 'size', 20), 0, w) : w * clamp(sv(s, 'size', 0.2), 0, 1))
const trapezoidInset = (s: Style, w: number): number => (isFixed(s) ? clamp(sv(s, 'size', 20), 0, w * 0.5) : w * clamp(sv(s, 'size', 0.2), 0, 0.5))

/** Outlines shared by shapes and their perimeters, in a 0..w × 0..h box. */
const POLYGONS = new Map<string, (w: number, h: number, s: Style) => Pt[]>([
  ['rhombus', (w, h) => [{ x: w / 2, y: 0 }, { x: w, y: h / 2 }, { x: w / 2, y: h }, { x: 0, y: h / 2 }]],
  ['triangle', (w, h) => [{ x: 0, y: 0 }, { x: w, y: h / 2 }, { x: 0, y: h }]],
  ['hexagon', (w, h, s) => {
    const d = hexagonInset(s, w)
    return [{ x: d, y: 0 }, { x: w - d, y: 0 }, { x: w, y: h / 2 }, { x: w - d, y: h }, { x: d, y: h }, { x: 0, y: h / 2 }]
  }],
  ['parallelogram', (w, h, s) => {
    const d = parallelogramInset(s, w)
    return [{ x: 0, y: h }, { x: d, y: 0 }, { x: w, y: 0 }, { x: w - d, y: h }]
  }],
  ['trapezoid', (w, h, s) => {
    const d = trapezoidInset(s, w)
    return [{ x: 0, y: h }, { x: d, y: 0 }, { x: w - d, y: 0 }, { x: w, y: h }]
  }],
  ['step', (w, h, s) => {
    const d = parallelogramInset(s, w)
    return [{ x: 0, y: 0 }, { x: w - d, y: 0 }, { x: w, y: h / 2 }, { x: w - d, y: h }, { x: 0, y: h }, { x: d, y: h / 2 }]
  }],
  ['card', (w, h, s) => {
    const d = clamp(sv(s, 'size', 30), 0, Math.min(w, h))
    return [{ x: d, y: 0 }, { x: w, y: 0 }, { x: w, y: h }, { x: 0, y: h }, { x: 0, y: d }]
  }],
  ['callout', (w, h, s) => {
    const d = clamp(sv(s, 'size', 30), 0, h)
    const dx = w * clamp(sv(s, 'position', 0.5), 0, 1)
    const dx2 = w * clamp(sv(s, 'position2', 0.5), 0, 1)
    const base = clamp(sv(s, 'base', 20), 0, w)
    return [{ x: 0, y: 0 }, { x: w, y: 0 }, { x: w, y: h - d }, { x: Math.min(w, dx + base), y: h - d }, { x: dx2, y: h }, { x: Math.max(0, dx), y: h - d }, { x: 0, y: h - d }]
  }],
  ['manualInput', (w, h, s) => {
    const d = Math.min(h, sv(s, 'size', 30))
    return [{ x: 0, y: h }, { x: 0, y: d }, { x: w, y: 0 }, { x: w, y: h }]
  }],
  ['corner', (w, h, s) => {
    const dx = clamp(sv(s, 'dx', 20), 0, w)
    const dy = clamp(sv(s, 'dy', 20), 0, h)
    return [{ x: 0, y: 0 }, { x: w, y: 0 }, { x: w, y: dy }, { x: dx, y: dy }, { x: dx, y: h }, { x: 0, y: h }]
  }],
  ['tee', (w, h, s) => {
    const dx = clamp(sv(s, 'dx', 20), 0, w)
    const dy = clamp(sv(s, 'dy', 20), 0, h)
    return [{ x: 0, y: 0 }, { x: w, y: 0 }, { x: w, y: dy }, { x: (w + dx) / 2, y: dy }, { x: (w + dx) / 2, y: h }, { x: (w - dx) / 2, y: h }, { x: (w - dx) / 2, y: dy }, { x: 0, y: dy }]
  }],
  ['singleArrow', (w, h, s) => {
    const aw = h * clamp(sv(s, 'arrowWidth', 0.3), 0, 1)
    const as = w * clamp(sv(s, 'arrowSize', 0.2), 0, 1)
    const at = (h - aw) / 2
    const ab = at + aw
    return [{ x: 0, y: at }, { x: w - as, y: at }, { x: w - as, y: 0 }, { x: w, y: h / 2 }, { x: w - as, y: h }, { x: w - as, y: ab }, { x: 0, y: ab }]
  }],
  ['doubleArrow', (w, h, s) => {
    const aw = h * clamp(sv(s, 'arrowWidth', 0.3), 0, 1)
    const as = w * clamp(sv(s, 'arrowSize', 0.2), 0, 1)
    const at = (h - aw) / 2
    const ab = at + aw
    return [{ x: 0, y: h / 2 }, { x: as, y: 0 }, { x: as, y: at }, { x: w - as, y: at }, { x: w - as, y: 0 }, { x: w, y: h / 2 }, { x: w - as, y: h }, { x: w - as, y: ab }, { x: as, y: ab }, { x: as, y: h }]
  }],
  ['loopLimit', (w, h, s) => {
    const d = Math.min(w / 2, Math.min(h, sv(s, 'size', 20)))
    return [{ x: d, y: 0 }, { x: w - d, y: 0 }, { x: w, y: d * 0.8 }, { x: w, y: h }, { x: 0, y: h }, { x: 0, y: d * 0.8 }]
  }],
  ['offPageConnector', (w, h, s) => {
    const d = h * clamp(sv(s, 'size', 3 / 8), 0, 1)
    return [{ x: 0, y: 0 }, { x: w, y: 0 }, { x: w, y: h - d }, { x: w / 2, y: h }, { x: 0, y: h - d }]
  }],
])

const polygonOf = (name: string, w: number, h: number, s: Style): Pt[] => POLYGONS.get(name)?.(w, h, s) ?? []

const paintRect: Paint = (c, x, y, w, h, e) => {
  if (e.rounded) {
    const r = rectArc(e.style, w, h)
    c.roundrect(x, y, w, h, r, r)
  } else c.rect(x, y, w, h)
  c.fillAndStroke()
}

const paintEllipse: Paint = (c, x, y, w, h) => {
  c.ellipse(x, y, w, h)
  c.fillAndStroke()
}

const actor = (path: (c: Canvas, w: number, h: number, e: ShapeEnv) => void): Paint => (c, x, y, w, h, e) => {
  c.translate(x, y)
  c.begin()
  path(c, w, h, e)
  c.fillAndStroke()
}

const polygonShape = (name: string, exclude: number[] | null = null): Paint =>
  actor((c, w, h, e) => addPoints(c, polygonOf(name, w, h, e.style), e.rounded, lineArc(e.style), true, exclude))

/** mxCylinder: the background path is filled and stroked, then the foreground path is stroked. */
const cylinderLike = (path: (c: Canvas, w: number, h: number, e: ShapeEnv, foreground: boolean) => void): Paint => (c, x, y, w, h, e) => {
  c.translate(x, y)
  c.begin()
  path(c, w, h, e, false)
  c.fillAndStroke()
  c.begin()
  path(c, w, h, e, true)
  c.stroke()
}

const after = (base: Paint, extra: Paint): Paint => (c, x, y, w, h, e) => {
  base(c, x, y, w, h, e)
  extra(c, x, y, w, h, e)
}

function strokeSegments(c: Canvas, segments: Array<[number, number, number, number]>): void {
  c.begin()
  for (const [x1, y1, x2, y2] of segments) {
    c.moveTo(x1, y1)
    c.lineTo(x2, y2)
  }
  c.stroke()
}

const swimlaneHorizontal = (s: Style): boolean => s.horizontal !== '0'
const swimlaneStart = (s: Style, w: number, h: number): number =>
  clamp(sv(s, 'startSize', 40), 0, swimlaneHorizontal(s) ? h : w)

/** mxSwimlane: header filled with fillColor, body with swimlaneFillColor, optional divider and rounding. */
const paintSwimlane: Paint = (c, x, y, w, h, e) => {
  const s = e.style
  const horizontal = swimlaneHorizontal(s)
  const start = swimlaneStart(s, w, h)
  const head = s.swimlaneHead !== '0'
  const body = s.swimlaneBody !== '0'
  const fill = e.laneFill
  const r = !e.rounded ? 0 : s.absoluteArcSize === '1'
    ? Math.min(w / 2, h / 2, sv(s, 'arcSize', 20) / 2)
    : Math.min(w / 2, h / 2, start * (sv(s, 'arcSize', 15) / 100) * 3)
  c.translate(x, y)
  c.begin()
  if (horizontal) {
    c.moveTo(w, start)
    c.lineTo(w, r)
    if (r > 0) c.quadTo(w, 0, w - Math.min(w / 2, r), 0)
    c.lineTo(Math.min(w / 2, r), 0)
    if (r > 0) c.quadTo(0, 0, 0, r)
    c.lineTo(0, start)
  } else {
    c.moveTo(start, 0)
    c.lineTo(r, 0)
    if (r > 0) c.quadTo(0, 0, 0, Math.min(h / 2, r))
    c.lineTo(0, h - Math.min(h / 2, r))
    if (r > 0) c.quadTo(0, h, r, h)
    c.lineTo(start, h)
  }
  if (head) c.fillAndStroke()
  else c.fill()
  if (start < (horizontal ? h : w)) {
    if (fill !== 'none') c.setFillColor(fill)
    c.begin()
    if (horizontal) {
      c.moveTo(0, start)
      c.lineTo(0, h - r)
      if (r > 0) c.quadTo(0, h, Math.min(w / 2, r), h)
      c.lineTo(w - Math.min(w / 2, r), h)
      if (r > 0) c.quadTo(w, h, w, h - r)
      c.lineTo(w, start)
    } else {
      c.moveTo(start, h)
      c.lineTo(w - r, h)
      if (r > 0) c.quadTo(w, h, w, h - Math.min(h / 2, r))
      c.lineTo(w, Math.min(h / 2, r))
      if (r > 0) c.quadTo(w, 0, w - r, 0)
      c.lineTo(start, 0)
    }
    if (body) {
      if (fill === 'none') c.stroke()
      else c.fillAndStroke()
    } else if (fill !== 'none') c.fill()
  }
  if (s.swimlaneLine !== '0' && start > 0 && start < (horizontal ? h : w)) {
    strokeSegments(c, [horizontal ? [0, start, w, start] : [start, 0, start, h]])
  }
}

const swimlaneLabel = (r: Box, e: ShapeEnv): Box => {
  const start = swimlaneStart(e.style, r.w, r.h)
  if (start === 0) return r
  return swimlaneHorizontal(e.style) ? { x: r.x, y: r.y, w: r.w, h: start } : { x: r.x, y: r.y, w: start, h: r.h }
}

/** PartialRectangleShape: fill, then only the sides whose top/right/bottom/left flag is on. */
const paintPartialRect: Paint = (c, x, y, w, h, e) => {
  const s = e.style
  c.save()
  c.setStrokeColor(null)
  c.rect(x, y, w, h)
  c.fill()
  c.restore()
  c.setLineCap('square')
  c.begin()
  c.moveTo(x, y)
  if (s.top !== '0') c.lineTo(x + w, y)
  else c.moveTo(x + w, y)
  if (s.right !== '0') c.lineTo(x + w, y + h)
  else c.moveTo(x + w, y + h)
  if (s.bottom !== '0') c.lineTo(x, y + h)
  else c.moveTo(x, y + h)
  if (s.left !== '0') c.lineTo(x, y)
  c.stroke()
  c.setLineCap('flat')
}

/** TableShape: a swimlane with a header, else a (rounded or partial) rectangle; grid lines are drawn after the rows. */
const paintTable: Paint = (c, x, y, w, h, e) => {
  const start = swimlaneStart(e.style, w, h)
  if (start === 0 && e.rounded) {
    const r = rectArc(e.style, w, h)
    c.roundrect(x, y, w, h, r, r)
    c.fillAndStroke()
  } else if (start === 0) paintPartialRect(c, x, y, w, h, e)
  else paintSwimlane(c, x, y, w, h, e)
}

const cylinderSize = (s: Style, h: number): number =>
  (s.size !== undefined ? h * clamp(sv(s, 'size', 0.15), 0, 1) : Math.min(40, Math.round(h / 5)))

const processInset = (s: Style, w: number, h: number, rounded: boolean): number => {
  let inset = sv(s, 'size', 0.1)
  inset = isFixed(s) ? clamp(inset, 0, w) : w * clamp(inset, 0, 1)
  if (rounded) {
    const f = sv(s, 'arcSize', 15) / 100
    inset = Math.max(inset, Math.min(w * f, h * f))
  }
  return Math.round(inset)
}

/**
 * A `data:` image URI usable in SVG, or null. draw.io stores base64 images
 * without `;base64` (the style separator would split it), so the marker is
 * restored when the payload is plain base64.
 */
function dataImageUri(value: string | undefined): string | null {
  if (value === undefined) return null
  const m = /^data:(image\/(?:png|jpe?g|gif|webp|bmp|svg\+xml))(;base64)?,([\s\S]*)$/i.exec(value.trim())
  if (m === null) return null
  const payload = m[3] ?? ''
  if (m[2] === undefined && /^[A-Za-z0-9+/=\s]+$/.test(payload)) return `data:${m[1] ?? ''};base64,${payload}`
  return value.trim()
}

const SHAPES = new Map<string, ShapeDef>()
const defineShape = (names: string[], def: ShapeDef): void => {
  for (const name of names) SHAPES.set(name, def)
}

defineShape(['rectangle', 'rect', 'label'], { paint: paintRect })
defineShape(['ellipse'], { paint: paintEllipse })
defineShape(['doubleEllipse'], {
  paint: (c, x, y, w, h, e) => {
    paintEllipse(c, x, y, w, h, e)
    const m = sv(e.style, 'margin', Math.min(3 + e.sw, Math.min(w / 5, h / 5)))
    if (w - 2 * m > 0 && h - 2 * m > 0) {
      c.ellipse(x + m, y + m, w - 2 * m, h - 2 * m)
      c.stroke()
    }
  },
  labelBounds: (r, e) => {
    const m = sv(e.style, 'margin', Math.min(3 + e.sw, Math.min(r.w / 5, r.h / 5)))
    return { x: r.x + m, y: r.y + m, w: r.w - 2 * m, h: r.h - 2 * m }
  },
})
defineShape(['rhombus'], {
  paint: (c, x, y, w, h, e) => {
    c.begin()
    addPoints(c, polygonOf('rhombus', w, h, e.style).map(p => ({ x: x + p.x, y: y + p.y })), e.rounded, lineArc(e.style), true)
    c.fillAndStroke()
  },
})
for (const name of ['triangle', 'hexagon', 'parallelogram', 'trapezoid', 'step', 'card', 'corner', 'tee', 'singleArrow', 'doubleArrow', 'loopLimit', 'offPageConnector']) {
  defineShape([name], { paint: polygonShape(name) })
}
defineShape(['callout'], { paint: polygonShape('callout', [4]), margins: (_w, _h, e) => margins(0, 0, 0, sv(e.style, 'size', 30)) })
defineShape(['manualInput'], {
  paint: polygonShape('manualInput'),
  margins: (_w, _h, e) => (boundedLabel(e.style) ? margins(0, sv(e.style, 'size', 30)) : null),
})
defineShape(['document'], {
  paint: actor((c, w, h, e) => {
    const dy = h * clamp(sv(e.style, 'size', 0.3), 0, 1)
    c.moveTo(0, 0)
    c.lineTo(w, 0)
    c.lineTo(w, h - dy / 2)
    c.quadTo((w * 3) / 4, h - dy * 1.4, w / 2, h - dy / 2)
    c.quadTo(w / 4, h - dy * (1 - 1.4), 0, h - dy / 2)
    c.lineTo(0, dy / 2)
    c.close()
  }),
  margins: (_w, h, e) => (boundedLabel(e.style) ? margins(0, 0, 0, sv(e.style, 'size', 0.3) * h) : null),
})
defineShape(['tape'], {
  paint: actor((c, w, h, e) => {
    const dy = h * clamp(sv(e.style, 'size', 0.4), 0, 1)
    c.moveTo(0, dy / 2)
    c.quadTo(w / 4, dy * 1.4, w / 2, dy / 2)
    c.quadTo((w * 3) / 4, dy * (1 - 1.4), w, dy / 2)
    c.lineTo(w, h - dy / 2)
    c.quadTo((w * 3) / 4, h - dy * 1.4, w / 2, h - dy / 2)
    c.quadTo(w / 4, h - dy * (1 - 1.4), 0, h - dy / 2)
    c.lineTo(0, dy / 2)
    c.close()
  }),
  labelBounds: (r, e) => {
    if (!boundedLabel(e.style)) return r
    const size = sv(e.style, 'size', 0.4)
    const d = e.style.direction ?? 'east'
    if (d === 'east' || d === 'west') return { x: r.x, y: r.y + r.h * size, w: r.w, h: r.h - 2 * r.h * size }
    return { x: r.x + r.w * size, y: r.y, w: r.w - 2 * r.w * size, h: r.h }
  },
})
defineShape(['note'], {
  paint: (c, x, y, w, h, e) => {
    const s = clamp(sv(e.style, 'size', 30), 0, Math.min(w, h))
    const op = clamp(sv(e.style, 'darkOpacity', 0), -1, 1)
    c.translate(x, y)
    c.begin()
    addPoints(c, [{ x: 0, y: 0 }, { x: w - s, y: 0 }, { x: w, y: s }, { x: w, y: h }, { x: 0, y: h }], false, 0, true)
    c.fillAndStroke()
    if (op !== 0) {
      c.save()
      c.setFillAlpha(Math.abs(op))
      c.setFillColor(op < 0 ? '#FFFFFF' : '#000000')
      c.begin()
      addPoints(c, [{ x: w - s, y: 0 }, { x: w - s, y: s }, { x: w, y: s }], false, 0, true)
      c.fill()
      c.restore()
    }
    c.begin()
    c.moveTo(w - s, 0)
    c.lineTo(w - s, s)
    c.lineTo(w, s)
    c.stroke()
  },
})
defineShape(['cube'], {
  paint: (c, x, y, w, h, e) => {
    const s = clamp(sv(e.style, 'size', 20), 0, Math.min(w, h))
    const op = clamp(sv(e.style, 'darkOpacity', 0), -1, 1)
    const op2 = clamp(sv(e.style, 'darkOpacity2', 0), -1, 1)
    c.translate(x, y)
    c.begin()
    addPoints(c, [{ x: 0, y: 0 }, { x: w - s, y: 0 }, { x: w, y: s }, { x: w, y: h }, { x: s, y: h }, { x: 0, y: h - s }], false, 0, true)
    c.fillAndStroke()
    for (const [opacity, pts] of [
      [op, [{ x: 0, y: 0 }, { x: w - s, y: 0 }, { x: w, y: s }, { x: s, y: s }]],
      [op2, [{ x: 0, y: 0 }, { x: s, y: s }, { x: s, y: h }, { x: 0, y: h - s }]],
    ] as Array<[number, Pt[]]>) {
      if (opacity === 0) continue
      c.save()
      c.setFillAlpha(Math.abs(opacity))
      c.setFillColor(opacity < 0 ? '#FFFFFF' : '#000000')
      c.begin()
      addPoints(c, pts, false, 0, true)
      c.fill()
      c.restore()
    }
    c.begin()
    c.moveTo(s, h)
    c.lineTo(s, s)
    c.lineTo(0, 0)
    c.moveTo(s, s)
    c.lineTo(w, s)
    c.stroke()
  },
  margins: (_w, _h, e) => {
    if (!boundedLabel(e.style)) return null
    const s = sv(e.style, 'size', 20)
    return margins(s, s)
  },
})
defineShape(['folder'], {
  paint: (c, x, y, w, h, e) => {
    const s = e.style
    let dx = clamp(sv(s, 'tabWidth', 60), 0, w)
    const dy = clamp(sv(s, 'tabHeight', 20), 0, h)
    const left = s.tabPosition === 'left'
    let arcSize = sv(s, 'arcSize', 0.1)
    if (s.absoluteArcSize !== '1') arcSize = Math.min(w, h) * arcSize
    arcSize = Math.min(arcSize, w * 0.5, (h - dy) * 0.5)
    dx = Math.min(w - arcSize, Math.max(dx, arcSize))
    if (!e.rounded) arcSize = 0
    c.translate(x, y)
    c.begin()
    if (left) {
      c.moveTo(Math.max(arcSize, 0), dy)
      c.lineTo(Math.max(arcSize, 0), 0)
      c.lineTo(dx, 0)
      c.lineTo(dx, dy)
    } else {
      c.moveTo(w - dx, dy)
      c.lineTo(w - dx, 0)
      c.lineTo(w - Math.max(arcSize, 0), 0)
      c.lineTo(w - Math.max(arcSize, 0), dy)
    }
    if (arcSize > 0) {
      c.moveTo(0, arcSize + dy)
      c.arcTo(arcSize, arcSize, 0, 0, 1, arcSize, dy)
      c.lineTo(w - arcSize, dy)
      c.arcTo(arcSize, arcSize, 0, 0, 1, w, arcSize + dy)
      c.lineTo(w, h - arcSize)
      c.arcTo(arcSize, arcSize, 0, 0, 1, w - arcSize, h)
      c.lineTo(arcSize, h)
      c.arcTo(arcSize, arcSize, 0, 0, 1, 0, h - arcSize)
    } else {
      c.moveTo(0, dy)
      c.lineTo(w, dy)
      c.lineTo(w, h)
      c.lineTo(0, h)
    }
    c.close()
    c.fillAndStroke()
    if (s.folderSymbol === 'triangle') {
      c.begin()
      addPoints(c, [{ x: w - 30, y: dy + 20 }, { x: w - 20, y: dy + 10 }, { x: w - 10, y: dy + 20 }], false, 0, true)
      c.stroke()
    }
  },
  margins: (_w, h, e) => (boundedLabel(e.style) ? margins(0, Math.min(h, sv(e.style, 'tabHeight', 15))) : null),
})
defineShape(['process'], {
  paint: after(paintRect, (c, x, y, w, h, e) => {
    const inset = processInset(e.style, w, h, e.rounded)
    strokeSegments(c, [[x + inset, y, x + inset, y + h], [x + w - inset, y, x + w - inset, y + h]])
  }),
  labelBounds: (r, e) => {
    const d = e.style.direction ?? 'east'
    if ((e.style.horizontal !== '0') !== (d === 'east' || d === 'west')) return r
    const inset = processInset(e.style, r.w, r.h, e.rounded)
    return { x: r.x + inset, y: r.y, w: r.w - 2 * inset, h: r.h }
  },
})
defineShape(['internalStorage'], {
  paint: after(paintRect, (c, x, y, w, h, e) => {
    let inset = 0
    if (e.rounded) {
      const f = sv(e.style, 'arcSize', 15) / 100
      inset = Math.min(w * f, h * f)
    }
    const dx = Math.max(inset, Math.min(w, sv(e.style, 'dx', 20)))
    const dy = Math.max(inset, Math.min(h, sv(e.style, 'dy', 20)))
    strokeSegments(c, [[x, y + dy, x + w, y + dy], [x + dx, y, x + dx, y + h]])
  }),
})
defineShape(['plus'], {
  paint: after(paintRect, (c, x, y, w, h) => {
    const border = Math.min(w / 5, h / 5) + 1
    strokeSegments(c, [[x + w / 2, y + border, x + w / 2, y + h - border], [x + border, y + h / 2, x + w - border, y + h / 2]])
  }),
})
defineShape(['dataStorage'], {
  paint: actor((c, w, h, e) => {
    const s = isFixed(e.style) ? clamp(sv(e.style, 'size', 20), 0, w) : w * clamp(sv(e.style, 'size', 0.1), 0, 1)
    c.moveTo(s, 0)
    c.lineTo(w, 0)
    c.quadTo(w - s * 2, h / 2, w, h)
    c.lineTo(s, h)
    c.quadTo(s - s * 2, h / 2, s, 0)
    c.close()
  }),
})
defineShape(['or'], {
  paint: actor((c, w, h) => {
    c.moveTo(0, 0)
    c.quadTo(w, 0, w, h / 2)
    c.quadTo(w, h, 0, h)
    c.close()
  }),
})
defineShape(['xor'], {
  paint: actor((c, w, h) => {
    c.moveTo(0, 0)
    c.quadTo(w, 0, w, h / 2)
    c.quadTo(w, h, 0, h)
    c.quadTo(w / 2, h / 2, 0, 0)
    c.close()
  }),
})
defineShape(['delay'], {
  paint: actor((c, w, h) => {
    const dx = Math.min(w, h / 2)
    c.moveTo(0, 0)
    c.lineTo(w - dx, 0)
    c.quadTo(w, 0, w, h / 2)
    c.quadTo(w, h, w - dx, h)
    c.lineTo(0, h)
    c.close()
  }),
})
defineShape(['display'], {
  paint: actor((c, w, h, e) => {
    const dx = Math.min(w, h / 2)
    const s = Math.min(w - dx, Math.max(0, sv(e.style, 'size', 0.25)) * w)
    c.moveTo(0, h / 2)
    c.lineTo(s, 0)
    c.lineTo(w - dx, 0)
    c.quadTo(w, 0, w, h / 2)
    c.quadTo(w, h, w - dx, h)
    c.lineTo(s, h)
    c.close()
  }),
})
defineShape(['cross'], {
  paint: actor((c, w, h, e) => {
    const m = Math.min(h, w)
    const size = clamp(m * sv(e.style, 'size', 0.2), 0, m)
    const t = (h - size) / 2
    const b = t + size
    const l = (w - size) / 2
    const r = l + size
    addPoints(c, [{ x: 0, y: t }, { x: l, y: t }, { x: l, y: 0 }, { x: r, y: 0 }, { x: r, y: t }, { x: w, y: t }, { x: w, y: b }, { x: r, y: b }, { x: r, y: h }, { x: l, y: h }, { x: l, y: b }, { x: 0, y: b }], false, 0, true)
  }),
})
defineShape(['crossbar'], {
  paint: actor((c, w, h) => {
    c.moveTo(0, 0)
    c.lineTo(0, h)
    c.moveTo(w, 0)
    c.lineTo(w, h)
    c.moveTo(0, h / 2)
    c.lineTo(w, h / 2)
  }),
})
defineShape(['curlyBracket'], {
  paint: actor((c, w, h, e) => {
    c.setFillColor(null)
    const s = w * clamp(sv(e.style, 'size', 0.5), 0, 1)
    addPoints(c, [{ x: w, y: 0 }, { x: s, y: 0 }, { x: s, y: h / 2 }, { x: 0, y: h / 2 }, { x: s, y: h / 2 }, { x: s, y: h }, { x: w, y: h }], e.rounded, lineArc(e.style), false)
  }),
})
defineShape(['cloud'], {
  paint: actor((c, w, h) => {
    c.moveTo(0.25 * w, 0.25 * h)
    c.curveTo(0.05 * w, 0.25 * h, 0, 0.5 * h, 0.16 * w, 0.55 * h)
    c.curveTo(0, 0.66 * h, 0.18 * w, 0.9 * h, 0.31 * w, 0.8 * h)
    c.curveTo(0.4 * w, h, 0.7 * w, h, 0.8 * w, 0.8 * h)
    c.curveTo(w, 0.8 * h, w, 0.6 * h, 0.875 * w, 0.5 * h)
    c.curveTo(w, 0.3 * h, 0.8 * w, 0.1 * h, 0.625 * w, 0.2 * h)
    c.curveTo(0.5 * w, 0.05 * h, 0.3 * w, 0.05 * h, 0.25 * w, 0.25 * h)
    c.close()
  }),
})
defineShape(['actor'], {
  paint: actor((c, w, h) => {
    const width = w / 3
    c.moveTo(0, h)
    c.curveTo(0, (3 * h) / 5, 0, (2 * h) / 5, w / 2, (2 * h) / 5)
    c.curveTo(w / 2 - width, (2 * h) / 5, w / 2 - width, 0, w / 2, 0)
    c.curveTo(w / 2 + width, 0, w / 2 + width, (2 * h) / 5, w / 2, (2 * h) / 5)
    c.curveTo(w, (2 * h) / 5, w, (3 * h) / 5, w, h)
    c.close()
  }),
})
defineShape(['cylinder'], {
  paint: cylinderLike((c, w, h, e, fg) => {
    const dy = cylinderSize(e.style, h)
    const filled = e.fill !== 'none'
    if ((fg && filled) || (!fg && !filled)) {
      c.moveTo(0, dy)
      c.curveTo(0, 2 * dy, w, 2 * dy, w, dy)
      if (!fg) {
        c.stroke()
        c.begin()
      }
    }
    if (!fg) {
      c.moveTo(0, dy)
      c.curveTo(0, -dy / 3, w, -dy / 3, w, dy)
      c.lineTo(w, h - dy)
      c.curveTo(w, h + dy / 3, 0, h + dy / 3, 0, h - dy)
      c.close()
    }
  }),
  margins: (_w, h, e) => (boundedLabel(e.style) ? margins(0, Math.min(40, h * sv(e.style, 'size', 0.15) * 2)) : null),
})
defineShape(['cylinder3'], {
  paint: (c, x, y, w, h, e) => {
    const size = clamp(sv(e.style, 'size', 15), 0, h * 0.5)
    const lid = e.style.lid !== '0'
    c.translate(x, y)
    if (size === 0) {
      c.rect(0, 0, w, h)
      c.fillAndStroke()
      return
    }
    c.begin()
    if (lid) {
      c.moveTo(0, size)
      c.arcTo(w * 0.5, size, 0, 0, 1, w * 0.5, 0)
      c.arcTo(w * 0.5, size, 0, 0, 1, w, size)
    } else {
      c.moveTo(0, 0)
      c.arcTo(w * 0.5, size, 0, 0, 0, w * 0.5, size)
      c.arcTo(w * 0.5, size, 0, 0, 0, w, 0)
    }
    c.lineTo(w, h - size)
    c.arcTo(w * 0.5, size, 0, 0, 1, w * 0.5, h)
    c.arcTo(w * 0.5, size, 0, 0, 1, 0, h - size)
    c.close()
    c.fillAndStroke()
    if (lid) {
      c.begin()
      c.moveTo(w, size)
      c.arcTo(w * 0.5, size, 0, 0, 1, w * 0.5, 2 * size)
      c.arcTo(w * 0.5, size, 0, 0, 1, 0, size)
      c.stroke()
    }
  },
  margins: (_w, h, e) => {
    if (!boundedLabel(e.style)) return null
    const size = sv(e.style, 'size', 15) / (e.style.lid === '0' ? 2 : 1)
    return margins(0, Math.min(h, size * 2), 0, Math.max(0, size * 0.3))
  },
})
defineShape(['datastore'], {
  paint: cylinderLike((c, w, h, e, fg) => {
    const dy = Math.min(h / 2, Math.round(h / 8) + e.sw - 1)
    const filled = e.fill !== 'none'
    if ((fg && filled) || (!fg && !filled)) {
      for (let k = 0; k < 3; k += 1) {
        c.moveTo(0, dy)
        c.curveTo(0, 2 * dy, w, 2 * dy, w, dy)
        if (!fg) {
          c.stroke()
          c.begin()
        }
        c.translate(0, k < 2 ? dy / 2 : -dy)
      }
    }
    if (!fg) {
      c.moveTo(0, dy)
      c.curveTo(0, -dy / 3, w, -dy / 3, w, dy)
      c.lineTo(w, h - dy)
      c.curveTo(w, h + dy / 3, 0, h + dy / 3, 0, h - dy)
      c.close()
    }
  }),
  margins: (_w, h, e) => margins(0, 2.5 * Math.min(h / 2, Math.round(h / 8) + e.sw - 1)),
})
defineShape(['message'], {
  paint: cylinderLike((c, w, h, _e, fg) => {
    if (fg) {
      c.moveTo(0, 0)
      c.lineTo(w / 2, h / 2)
      c.lineTo(w, 0)
    } else {
      addPoints(c, [{ x: 0, y: 0 }, { x: w, y: 0 }, { x: w, y: h }, { x: 0, y: h }], false, 0, true)
    }
  }),
})
const jettyShape = (jettyWidth: number, jettyHeight: number, positions: (h: number, dy: number) => [number, number]): Paint =>
  cylinderLike((c, w, h, e, fg) => {
    const dx = sv(e.style, 'jettyWidth', jettyWidth)
    const dy = sv(e.style, 'jettyHeight', jettyHeight)
    const x0 = dx / 2
    const x1 = x0 + dx / 2
    const [y0, y1] = positions(h, dy)
    if (fg) {
      c.moveTo(x0, y0)
      c.lineTo(x1, y0)
      c.lineTo(x1, y0 + dy)
      c.lineTo(x0, y0 + dy)
      c.moveTo(x0, y1)
      c.lineTo(x1, y1)
      c.lineTo(x1, y1 + dy)
      c.lineTo(x0, y1 + dy)
    } else {
      addPoints(c, [{ x: x0, y: 0 }, { x: w, y: 0 }, { x: w, y: h }, { x: x0, y: h }, { x: x0, y: y1 + dy }, { x: 0, y: y1 + dy }, { x: 0, y: y1 }, { x: x0, y: y1 }, { x: x0, y: y0 + dy }, { x: 0, y: y0 + dy }, { x: 0, y: y0 }, { x: x0, y: y0 }], false, 0, true)
    }
  })
defineShape(['module'], {
  paint: jettyShape(20, 10, (h, dy) => {
    const y0 = Math.min(dy, h - dy)
    return [y0, Math.min(y0 + 2 * dy, h - dy)]
  }),
})
defineShape(['component'], { paint: jettyShape(32, 12, (h, dy) => [0.3 * h - dy / 2, 0.7 * h - dy / 2]) })
defineShape(['line'], {
  paint: (c, x, y, w, h) => strokeSegments(c, [[x, y + h / 2, x + w, y + h / 2]]),
})
const ellipseWith = (segments: (x: number, y: number, w: number, h: number) => Array<[number, number, number, number]>): Paint =>
  after(paintEllipse, (c, x, y, w, h) => strokeSegments(c, segments(x, y, w, h)))
defineShape(['tapeData'], { paint: ellipseWith((x, y, w, h) => [[x + w / 2, y + h, x + w, y + h]]) })
defineShape(['orEllipse'], { paint: ellipseWith((x, y, w, h) => [[x, y + h / 2, x + w, y + h / 2], [x + w / 2, y, x + w / 2, y + h]]) })
defineShape(['sumEllipse'], {
  paint: ellipseWith((x, y, w, h) => {
    const s = 0.145
    return [[x + w * s, y + h * s, x + w * (1 - s), y + h * (1 - s)], [x + w * (1 - s), y + h * s, x + w * s, y + h * (1 - s)]]
  }),
})
defineShape(['lineEllipse'], {
  paint: (c, x, y, w, h, e) => {
    paintEllipse(c, x, y, w, h, e)
    strokeSegments(c, [e.style.line === 'vertical' ? [x + w / 2, y, x + w / 2, y + h] : [x, y + h / 2, x + w, y + h / 2]])
  },
})
defineShape(['umlEntity'], { paint: ellipseWith((x, y, w, h) => [[x + w / 8, y + h, x + (w * 7) / 8, y + h]]) })
defineShape(['sortShape'], {
  paint: (c, x, y, w, h, e) => {
    SHAPES.get('rhombus')?.paint(c, x, y, w, h, e)
    strokeSegments(c, [[x, y + h / 2, x + w, y + h / 2]])
  },
})
defineShape(['collate'], {
  paint: (c, x, y, w, h) => {
    c.begin()
    addPoints(c, [{ x, y }, { x: x + w, y }, { x: x + w / 2, y: y + h / 2 }], false, 0, true)
    c.fillAndStroke()
    c.begin()
    addPoints(c, [{ x, y: y + h }, { x: x + w, y: y + h }, { x: x + w / 2, y: y + h / 2 }], false, 0, true)
    c.fillAndStroke()
  },
})
defineShape(['umlActor'], {
  paint: (c, x, y, w, h) => {
    c.translate(x, y)
    c.ellipse(w / 4, 0, w / 2, h / 4)
    c.fillAndStroke()
    strokeSegments(c, [[w / 2, h / 4, w / 2, (2 * h) / 3], [w / 2, h / 3, 0, h / 3], [w / 2, h / 3, w, h / 3], [w / 2, (2 * h) / 3, 0, h], [w / 2, (2 * h) / 3, w, h]])
  },
})
defineShape(['umlBoundary'], {
  paint: (c, x, y, w, h) => {
    c.translate(x, y)
    strokeSegments(c, [[0, h / 4, 0, (h * 3) / 4], [0, h / 2, w / 6, h / 2]])
    c.ellipse(w / 6, 0, (w * 5) / 6, h)
    c.fillAndStroke()
  },
  margins: w => margins(w / 6),
})
defineShape(['umlControl'], {
  paint: (c, x, y, w, h) => {
    c.translate(x, y)
    strokeSegments(c, [[(w * 3) / 8, (h / 8) * 1.1, (w * 5) / 8, 0]])
    c.ellipse(0, h / 8, w, (h * 7) / 8)
    c.fillAndStroke()
    strokeSegments(c, [[(w * 3) / 8, (h / 8) * 1.1, (w * 5) / 8, h / 4]])
  },
  labelBounds: r => ({ x: r.x, y: r.y + r.h / 8, w: r.w, h: (r.h * 7) / 8 }),
})
defineShape(['umlDestroy'], {
  paint: (c, x, y, w, h) => strokeSegments(c, [[x + w, y, x, y + h], [x, y, x + w, y + h]]),
})
defineShape(['umlLifeline'], {
  paint: (c, x, y, w, h, e) => {
    const size = clamp(sv(e.style, 'size', 40), 0, h)
    const participant = e.style.participant
    const head = participant === undefined || participant === 'umlLifeline' ? undefined : SHAPES.get(participant)
    if (participant !== undefined && head === undefined) {
      e.note('unsupported', `participant=${participant}`, `lifeline participant "${participant}" is not supported; drawn as a rectangle`)
    }
    c.save()
      ; (head?.paint ?? paintRect)(c, x, y, w, size, e)
    c.restore()
    if (size < h) {
      c.setDashed(e.style.lifelineDashed !== '0')
      if (e.style.lifelineColor !== undefined) c.setStrokeColor(resolveColor(e.style.lifelineColor, e.stroke, 'lifelineColor', e.note))
      strokeSegments(c, [[x + w / 2, y + size, x + w / 2, y + h]])
    }
  },
  labelBounds: (r, e) => ({ x: r.x, y: r.y, w: r.w, h: clamp(sv(e.style, 'size', 40), 0, r.h) }),
})
defineShape(['umlFrame'], {
  paint: (c, x, y, w, h, e) => {
    const corner = 10
    const w0 = Math.min(w, Math.max(corner, sv(e.style, 'width', 60)))
    const h0 = Math.min(h, Math.max(corner * 1.5, sv(e.style, 'height', 30)))
    if (e.laneFill !== 'none') {
      c.save()
      c.setFillColor(e.laneFill)
      c.rect(x, y, w, h)
      c.fill()
      c.restore()
    }
    c.begin()
    addPoints(c, [{ x, y }, { x: x + w0, y }, { x: x + w0, y: y + Math.max(0, h0 - corner * 1.5) }, { x: x + Math.max(0, w0 - corner), y: y + h0 }, { x, y: y + h0 }], false, 0, true)
    c.fillAndStroke()
    c.begin()
    c.moveTo(x + w0, y)
    c.lineTo(x + w, y)
    c.lineTo(x + w, y + h)
    c.lineTo(x, y + h)
    c.lineTo(x, y + h0)
    c.stroke()
  },
  margins: (w, h, e) => margins(0, 0, w - sv(e.style, 'width', 60), h - sv(e.style, 'height', 30)),
})
defineShape(['lollipop'], {
  paint: (c, x, y, w, h, e) => {
    const sz = sv(e.style, 'size', 10)
    c.translate(x, y)
    c.ellipse((w - sz) / 2, 0, sz, sz)
    c.fillAndStroke()
    strokeSegments(c, [[w / 2, sz, w / 2, h]])
  },
})
defineShape(['requiredInterface'], {
  paint: (c, x, y, w, h) => {
    c.translate(x, y)
    c.begin()
    c.moveTo(0, 0)
    c.quadTo(w, 0, w, h / 2)
    c.quadTo(w, h, 0, h)
    c.stroke()
  },
})
defineShape(['providedRequiredInterface'], {
  paint: (c, x, y, w, h, e) => {
    const inset = sv(e.style, 'inset', 2) + e.sw
    c.translate(x, y)
    c.ellipse(0, inset, w - 2 * inset, h - 2 * inset)
    c.fillAndStroke()
    c.begin()
    c.moveTo(w / 2, 0)
    c.quadTo(w, 0, w, h / 2)
    c.quadTo(w, h, w / 2, h)
    c.stroke()
  },
})
const stateShape = (outer: boolean): Paint => (c, x, y, w, h) => {
  const inset = Math.min(4, Math.min(w / 5, h / 5))
  if (w > 0 && h > 0) {
    c.ellipse(x + inset, y + inset, w - 2 * inset, h - 2 * inset)
    c.fillAndStroke()
  }
  if (outer) {
    c.ellipse(x, y, w, h)
    c.stroke()
  }
}
defineShape(['endState'], { paint: stateShape(true) })
defineShape(['startState'], { paint: stateShape(false) })
defineShape(['partialRectangle'], { paint: paintPartialRect })
defineShape(['swimlane'], { paint: paintSwimlane, labelBounds: swimlaneLabel })
defineShape(['table', 'tableRow'], { paint: paintTable, labelBounds: swimlaneLabel })
defineShape(['image'], {
  paint: (c, x, y, w, h, e) => {
    const background = optionalColor(e.style.imageBackground, '#ffffff', 'imageBackground', e.note)
    const border = optionalColor(e.style.imageBorder, '#000000', 'imageBorder', e.note)
    if (background !== 'none') {
      c.save()
      c.setFillColor(background)
      c.rect(x, y, w, h)
      c.fill()
      c.restore()
    }
    const src = dataImageUri(e.style.image)
    if (src === null) {
      e.note('unsupported', 'image:external', 'only data: images are rendered; drawn as a placeholder')
      paintPlaceholder(c, x, y, w, h, 'image')
    } else {
      c.image(x, y, w, h, src, e.style.imageAspect !== '0')
    }
    if (border !== 'none') {
      c.save()
      c.setStrokeColor(border)
      c.rect(x, y, w, h)
      c.stroke()
      c.restore()
    }
  },
})

function paintPlaceholder(c: Canvas, x: number, y: number, w: number, h: number, name: string): void {
  c.save()
  c.setFillColor(null)
  c.setStrokeColor('#888888')
  c.setStrokeWidth(1)
  c.setDashed(true)
  c.setDashPattern('4 3', true)
  c.rect(x, y, w, h)
  c.stroke()
  c.restore()
  if (name !== '') c.raw(`<text x="${fmt(x + 3)}" y="${fmt(y + 10)}" font-family="Helvetica, Arial, sans-serif" font-size="8" fill="#888888">${esc(name)}</text>`)
}

/** mxUtils.getDirectedBounds: apply label margins in the shape's direction and flips. */
function directedBounds(rect: Box, m0: Margins, style: Style): Box {
  const d = style.direction ?? 'east'
  const flipH = style.flipH === '1'
  const flipV = style.flipV === '1'
  const m = {
    x: Math.round(clamp(m0.left, 0, rect.w)),
    y: Math.round(clamp(m0.top, 0, rect.h)),
    width: Math.round(clamp(m0.right, 0, rect.w)),
    height: Math.round(clamp(m0.bottom, 0, rect.h)),
  }
  const vertical = d === 'south' || d === 'north'
  if ((flipV && vertical) || (flipH && !vertical)) [m.x, m.width] = [m.width, m.x]
  if ((flipH && vertical) || (flipV && !vertical)) [m.y, m.height] = [m.height, m.y]
  let m2 = m
  if (d === 'south') m2 = { y: m.x, x: m.height, width: m.y, height: m.width }
  else if (d === 'west') m2 = { y: m.height, x: m.width, width: m.x, height: m.y }
  else if (d === 'north') m2 = { y: m.width, x: m.y, width: m.height, height: m.x }
  return { x: rect.x + m2.x, y: rect.y + m2.y, w: rect.w - m2.width - m2.x, h: rect.h - m2.height - m2.y }
}

/* ================================================================== *
 * Vertices
 * ================================================================== */

const DIRECTIONS = new Map([['east', 0], ['south', 90], ['west', 180], ['north', 270]])
const UNROTATED_KINDS = new Set(['swimlane', 'table', 'tableRow'])

function shapeKind(style: Style, note: Note): string {
  const shape = style.shape ?? 'rectangle'
  if (SHAPES.has(shape)) {
    if (shape === 'label' && style.image !== undefined) note('approximated', 'shape=label', 'the image of a label shape is not drawn')
    return shape
  }
  note('unsupported', `shape=${shape}`, `shape "${shape}" is not supported; drawn as a placeholder`)
  return 'unsupported'
}

function ellipsePoints(b: Box, count = 48): Pt[] {
  const c = center(b)
  return Array.from({ length: count }, (_, i) => {
    const a = (i / count) * Math.PI * 2
    return { x: c.x + (Math.cos(a) * b.w) / 2, y: c.y + (Math.sin(a) * b.h) / 2 }
  })
}

/**
 * Perimeter polygon for a `perimeter` style value in shape-box coordinates,
 * or null for centerPerimeter. As in draw.io, a shape without a perimeter
 * key uses its bounding rectangle.
 */
function perimeterOutline(name: string, b: Box, style: Style, note: Note): Pt[] | null {
  const shift = (pts: Pt[]): Pt[] => pts.map(p => ({ x: b.x + p.x, y: b.y + p.y }))
  switch (name) {
    case '':
    case 'rectanglePerimeter':
    case 'orthogonalPerimeter':
    case 'lifelinePerimeter':
    case 'backbonePerimeter':
      return corners(b)
    case 'ellipsePerimeter':
    case 'cloudPerimeter':
      return ellipsePoints(b)
    case 'rhombusPerimeter':
      return shift(polygonOf('rhombus', b.w, b.h, style))
    case 'trianglePerimeter':
      return shift(polygonOf('triangle', b.w, b.h, style))
    case 'hexagonPerimeter':
    case 'hexagonPerimeter2':
      return shift(polygonOf('hexagon', b.w, b.h, style))
    case 'parallelogramPerimeter':
      return shift(polygonOf('parallelogram', b.w, b.h, style))
    case 'trapezoidPerimeter':
      return shift(polygonOf('trapezoid', b.w, b.h, style))
    case 'stepPerimeter':
      return shift(polygonOf('step', b.w, b.h, style))
    case 'calloutPerimeter':
      return corners({ x: b.x, y: b.y, w: b.w, h: Math.max(0, b.h - clamp(sv(style, 'size', 30), 0, b.h)) })
    case 'centerPerimeter':
      return null
    default:
      note('approximated', `perimeter=${name}`, `perimeter "${name}" is not supported; using the bounding rectangle`)
      return corners(b)
  }
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
  if (UNROTATED_KINDS.has(kind)) dirDeg = 0
  const swapped = dirDeg === 90 || dirDeg === 270
  const shapeBox = swapped ? { x: c.x - box.h / 2, y: c.y - box.w / 2, w: box.h, h: box.w } : box
  const flip = scaleAbout(style.flipH === '1' ? -1 : 1, style.flipV === '1' ? -1 : 1, c)
  const cellMat = mul(rotateAbout(num(style.rotation, 0), c), flip)
  const shapeMat = mul(cellMat, rotateAbout(dirDeg, c))
  const local = perimeterOutline(style.perimeter ?? '', shapeBox, style, note)
  const outline = local === null ? [c] : local.map(p => apply(shapeMat, p))
  const bounds = local === null ? aabb(corners(shapeBox).map(p => apply(shapeMat, p))) : aabb(outline)
  return { style, box, center: c, cellMat, shapeMat, shapeBox, kind, outline, bounds, centerOnly: local === null }
}

function shapeEnv(ctx: Context, cell: Cell, note: Note): ShapeEnv {
  const style = cell.style
  let fill = cellColor(cell, 'fillColor', '#ffffff', note)
  const gradient = fill === 'none' ? 'none' : cellColor(cell, 'gradientColor', '#ffffff', note, true)
  if (gradient !== 'none') fill = ctx.gradient(fill, gradient, style.gradientDirection)
  return {
    style,
    cell,
    fill,
    stroke: cellColor(cell, 'strokeColor', '#000000', note),
    laneFill: cellColor(cell, 'swimlaneFillColor', '#ffffff', note, true),
    sw: Math.max(0, num(style.strokeWidth, 1)),
    rounded: style.rounded === '1',
    note,
  }
}

function canvasFor(style: Style, fill: string, stroke: string, sw: number): Canvas {
  const pattern = /^[0-9.]+(\s+[0-9.]+)*$/.test(style.dashPattern ?? '') ? (style.dashPattern ?? '3 3') : '3 3'
  return new Canvas({
    fill,
    stroke,
    strokeWidth: sw,
    dashed: style.dashed === '1',
    dashPattern: pattern,
    fixDash: style.fixDash === '1',
    fillAlpha: clamp(num(style.fillOpacity, 100), 0, 100) / 100,
    strokeAlpha: clamp(num(style.strokeOpacity, 100), 0, 100) / 100,
  })
}

function renderVertex(ctx: Context, cell: Cell, frame: Frame, note: Note): void {
  const style = cell.style
  const env = shapeEnv(ctx, cell, note)
  const c = canvasFor(style, env.fill, env.stroke, env.sw)
  const sb = frame.shapeBox
  const def = SHAPES.get(frame.kind)
  if (def === undefined) paintPlaceholder(c, sb.x, sb.y, sb.w, sb.h, style.shape ?? '')
  else def.paint(c, sb.x, sb.y, sb.w, sb.h, env)
  const extent = aabb(corners(sb).map(p => apply(frame.shapeMat, p)))
  const opacity = num(style.opacity, 100)
  const attrs = (opacity < 100 ? ` opacity="${fmt(Math.max(0, opacity) / 100)}"` : '') + ctx.shadow(style, extent, note)
  const inner = isIdentity(frame.shapeMat) ? c.parts.join('') : `<g${matAttr(frame.shapeMat)}>${c.parts.join('')}</g>`
  ctx.body.push(attrs === '' ? inner : `<g${attrs}>${inner}</g>`)
  ctx.bounds.addBox(extent)
  ctx.drawn += 1
  if (cell.label !== '' && style.noLabel !== '1') renderVertexLabel(ctx, cell, frame, def, env)
}

/**
 * Lay out a vertex label as draw.io does: when the label is inside the
 * shape, start from the shape's label bounds or margins (a swimlane header,
 * a cylinder below its lid, …); move the box beside the shape for
 * labelPosition / verticalLabelPosition; inset by the spacing keys; rotate
 * with the cell, and by -90° when horizontal=0.
 */
function renderVertexLabel(ctx: Context, cell: Cell, frame: Frame, def: ShapeDef | undefined, env: ShapeEnv): void {
  const style = cell.style
  const note = env.note
  const labelPosition = enumValue<HAlign>(style, 'labelPosition', H_ALIGNS, 'center', note)
  const verticalLabelPosition = enumValue<VAlign>(style, 'verticalLabelPosition', V_ALIGNS, 'middle', note)
  let rect = frame.box
  if (def !== undefined && labelPosition === 'center' && verticalLabelPosition === 'middle') {
    if (def.labelBounds !== undefined) rect = def.labelBounds(rect, env)
    else if (def.margins !== undefined) {
      const m = def.margins(rect.w, rect.h, env)
      if (m !== null) rect = directedBounds(rect, m, style)
    }
  }
  const outer = {
    x: rect.x + (labelPosition === 'left' ? -frame.box.w : labelPosition === 'right' ? frame.box.w : 0),
    y: rect.y + (verticalLabelPosition === 'top' ? -frame.box.h : verticalLabelPosition === 'bottom' ? frame.box.h : 0),
    w: rect.w,
    h: rect.h,
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
  const base = fontFromStyle(style, cellColor(cell, 'fontColor', '#000000', note))
  const parsed = parseLabel(cell.label, style, base, note)
  renderText(ctx, {
    lines: parsed.lines,
    spaceAfter: parsed.spaceAfter,
    base,
    box: inner,
    align: enumValue<HAlign>(style, 'align', H_ALIGNS, 'center', note),
    valign: enumValue<VAlign>(style, 'verticalAlign', V_ALIGNS, 'middle', note),
    wrap: style.whiteSpace === 'wrap',
    transform,
    background: optionalColor(style.labelBackgroundColor, '#ffffff', 'labelBackgroundColor', note),
    border: optionalColor(style.labelBorderColor, '#000000', 'labelBorderColor', note),
    opacity: num(style.textOpacity, 100),
    preserveSpace: !parsed.html,
    overflow: enumValue<string>(style, 'overflow', OVERFLOWS, 'visible', note),
  })
}

/**
 * Grid lines of a draw.io table, drawn above its rows like draw.io's
 * re-stroked cell borders: a line under every row but the last, and a line
 * right of every cell but the last in its row.
 */
function renderTableLines(ctx: Context, table: Cell, frame: Frame, note: Note): void {
  const style = table.style
  const rowLines = style.rowLines !== '0'
  const columnLines = style.columnLines !== '0'
  if (!rowLines && !columnLines) return
  const framed = (cell: Cell): Frame | null => (cell.vertex && cell.visible ? ctx.frames.get(cell.id) ?? null : null)
  const rows = table.children.filter(row => framed(row) !== null)
  const segments: string[] = []
  rows.forEach((row, i) => {
    const rb = (framed(row) as Frame).box
    if (rowLines && i < rows.length - 1) segments.push(`M ${fmt(frame.box.x)} ${fmt(rb.y + rb.h)} H ${fmt(frame.box.x + frame.box.w)}`)
    const cells = row.children.filter(cell => framed(cell) !== null)
    cells.forEach((cell, j) => {
      if (num(cell.style.rowspan, 1) > 1 || num(cell.style.colspan, 1) > 1) {
        note('approximated', 'table:span', 'merged table cells (rowspan/colspan) are drawn with unmerged grid lines')
      }
      if (columnLines && j < cells.length - 1) {
        const cb = (framed(cell) as Frame).box
        segments.push(`M ${fmt(cb.x + cb.w)} ${fmt(rb.y)} V ${fmt(rb.y + rb.h)}`)
      }
    })
  })
  const stroke = cellColor(table, 'strokeColor', '#000000', note)
  if (segments.length === 0 || stroke === 'none') return
  ctx.body.push(`<path d="${segments.join(' ')}" fill="none" stroke="${esc(stroke)}" stroke-width="${fmt(Math.max(0, num(style.strokeWidth, 1)))}"${matAttr(frame.cellMat)}/>`)
}

/* ================================================================== *
 * Edges
 * ================================================================== */

interface Port { pt: Pt; dir: Pt }
type Side = 'left' | 'right' | 'top' | 'bottom'

const SIDE_DIR: Record<Side, Pt> = { left: { x: -1, y: 0 }, right: { x: 1, y: 0 }, top: { x: 0, y: -1 }, bottom: { x: 0, y: 1 } }
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
  if (frame.centerOnly) return frame.center
  const dir = { x: toward.x - frame.center.x, y: toward.y - frame.center.y }
  if (Math.hypot(dir.x, dir.y) < 1e-9) return frame.center
  const ts = lineHits(frame.outline, frame.center, dir).filter(t => t > 1e-9)
  if (ts.length === 0) return frame.center
  const t = Math.min(...ts)
  return { x: frame.center.x + dir.x * t, y: frame.center.y + dir.y * t }
}

/** Slide p along dir's axis to the outermost outline point in direction dir. */
function projectOnAxis(frame: Frame, p: Pt, dir: Pt): Pt {
  if (frame.centerOnly) return frame.center
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

type MarkerFactory = (c: Canvas, pe: Pt, unitX: number, unitY: number, size: number, source: boolean, sw: number, filled: boolean) => (() => void)

const finish = (c: Canvas, filled: boolean): void => {
  if (filled) c.fillAndStroke()
  else c.stroke()
}

/** classic / block (mxMarker.createArrow): the line stops at the notch or the base. */
const arrowMarker = (widthFactor: number, notch: boolean): MarkerFactory => (c, pe, ux0, uy0, size, _source, sw, filled) => {
  const ox = ux0 * sw * 1.118
  const oy = uy0 * sw * 1.118
  const ux = ux0 * (size + sw)
  const uy = uy0 * (size + sw)
  const pt = { x: pe.x - ox, y: pe.y - oy }
  const f = notch ? 3 / 4 : 1
  pe.x += -ux * f - ox
  pe.y += -uy * f - oy
  return () => {
    c.begin()
    c.moveTo(pt.x, pt.y)
    c.lineTo(pt.x - ux - uy / widthFactor, pt.y - uy + ux / widthFactor)
    if (notch) c.lineTo(pt.x - (ux * 3) / 4, pt.y - (uy * 3) / 4)
    c.lineTo(pt.x + uy / widthFactor - ux, pt.y - uy - ux / widthFactor)
    c.close()
    finish(c, filled)
  }
}

const openMarker = (widthFactor: number): MarkerFactory => (c, pe, ux0, uy0, size, _source, sw) => {
  const ox = ux0 * sw * 1.118
  const oy = uy0 * sw * 1.118
  const ux = ux0 * (size + sw)
  const uy = uy0 * (size + sw)
  const pt = { x: pe.x - ox, y: pe.y - oy }
  pe.x += -ox * 2
  pe.y += -oy * 2
  return () => {
    c.begin()
    c.moveTo(pt.x - ux - uy / widthFactor, pt.y - uy + ux / widthFactor)
    c.lineTo(pt.x, pt.y)
    c.lineTo(pt.x + uy / widthFactor - ux, pt.y - uy - ux / widthFactor)
    c.stroke()
  }
}

const diamondMarker = (thin: boolean): MarkerFactory => (c, pe, ux0, uy0, size, _source, sw, filled) => {
  const swFactor = thin ? 0.9862 : 0.7071
  const ox = ux0 * sw * swFactor
  const oy = uy0 * sw * swFactor
  const ux = ux0 * (size + sw)
  const uy = uy0 * (size + sw)
  const pt = { x: pe.x - ox, y: pe.y - oy }
  pe.x += -ux - ox
  pe.y += -uy - oy
  const tk = thin ? 3.4 : 2
  return () => {
    c.begin()
    c.moveTo(pt.x, pt.y)
    c.lineTo(pt.x - ux / 2 - uy / tk, pt.y + ux / tk - uy / 2)
    c.lineTo(pt.x - ux, pt.y - uy)
    c.lineTo(pt.x - ux / 2 + uy / tk, pt.y - uy / 2 - ux / tk)
    c.close()
    finish(c, filled)
  }
}

const circleMarker: MarkerFactory = (c, pe, ux0, uy0, size0, _source, sw, filled) => {
  const size = size0 + sw
  const pt = { ...pe }
  pe.x -= ux0 * (2 * size + sw)
  pe.y -= uy0 * (2 * size + sw)
  const ux = ux0 * (size + sw)
  const uy = uy0 * (size + sw)
  return () => {
    c.ellipse(pt.x - ux - size, pt.y - uy - size, 2 * size, 2 * size)
    finish(c, filled)
  }
}

/** Crow's-foot family from draw.io's ER library: n is the marker length size + sw + 1. */
const erMarker = (paint: (c: Canvas, px: number, py: number, nx: number, ny: number) => void): MarkerFactory => (c, pe, ux, uy, size, _source, sw) => {
  const nx = ux * (size + sw + 1)
  const ny = uy * (size + sw + 1)
  return () => {
    c.begin()
    paint(c, pe.x, pe.y, nx, ny)
    c.stroke()
  }
}
const erBar = (c: Canvas, px: number, py: number, nx: number, ny: number, k: number): void => {
  c.moveTo(px - nx * k - ny / 2, py - ny * k + nx / 2)
  c.lineTo(px - nx * k + ny / 2, py - ny * k - nx / 2)
}
const erFoot = (c: Canvas, px: number, py: number, nx: number, ny: number): void => {
  c.moveTo(px + ny / 2, py - nx / 2)
  c.lineTo(px - nx, py - ny)
  c.lineTo(px - ny / 2, py + nx / 2)
}
/** ERzeroToOne / ERzeroToMany: a circle beyond a bar or foot; unfilled ones shorten the line to the circle. */
const erZeroMarker = (many: boolean): MarkerFactory => (c, pe, ux, uy, size, _source, sw, filled) => {
  const nx = ux * (size + sw + 1)
  const ny = uy * (size + sw + 1)
  const a = size / 2
  const px = pe.x
  const py = pe.y
  if (!filled) {
    pe.x -= 2 * nx - (ux * sw) / 2
    pe.y -= 2 * ny - (uy * sw) / 2
  }
  return () => {
    c.save()
    c.ellipse(px - 1.5 * nx - a, py - 1.5 * ny - a, 2 * a, 2 * a)
    if (filled) {
      c.setFillColor('#ffffff')
      c.fillAndStroke()
    } else c.stroke()
    c.restore()
    c.begin()
    if (many) erFoot(c, px, py, nx, ny)
    else erBar(c, px, py, nx, ny, 0.5)
    if (!filled) {
      c.moveTo(px - nx - (many ? 0 : (ux * sw) / 2), py - ny - (many ? 0 : (uy * sw) / 2))
      c.lineTo(px, py)
    }
    c.stroke()
  }
}

const MARKERS = new Map<string, MarkerFactory>([
  ['classic', arrowMarker(2, true)],
  ['classicThin', arrowMarker(3, true)],
  ['block', arrowMarker(2, false)],
  ['blockThin', arrowMarker(3, false)],
  ['open', openMarker(2)],
  ['openThin', openMarker(3)],
  ['oval', (c, pe, ux, uy, size, _source, _sw, filled) => {
    const a = size / 2
    const pt = { ...pe }
    pe.x -= ux * a
    pe.y -= uy * a
    return () => {
      c.ellipse(pt.x - a, pt.y - a, size, size)
      finish(c, filled)
    }
  }],
  ['diamond', diamondMarker(false)],
  ['diamondThin', diamondMarker(true)],
  ['doubleBlock', (c, pe, ux0, uy0, size, _source, sw, filled) => {
    const ox = ux0 * sw * 1.118
    const oy = uy0 * sw * 1.118
    const ux = ux0 * (size + sw)
    const uy = uy0 * (size + sw)
    const pt = { x: pe.x - ox, y: pe.y - oy }
    pe.x += -ux * 2 - ox
    pe.y += -uy * 2 - oy
    return () => {
      c.begin()
      c.moveTo(pt.x, pt.y)
      c.lineTo(pt.x - ux - uy / 2, pt.y - uy + ux / 2)
      c.lineTo(pt.x + uy / 2 - ux, pt.y - uy - ux / 2)
      c.close()
      c.moveTo(pt.x - ux, pt.y - uy)
      c.lineTo(pt.x - 2 * ux - 0.5 * uy, pt.y + 0.5 * ux - 2 * uy)
      c.lineTo(pt.x - 2 * ux + 0.5 * uy, pt.y - 0.5 * ux - 2 * uy)
      c.close()
      finish(c, filled)
    }
  }],
  ['baseDash', erMarker((c, px, py, nx, ny) => {
    c.moveTo(px - ny / 2, py + nx / 2)
    c.lineTo(px + ny / 2, py - nx / 2)
  })],
  ['dash', erMarker((c, px, py, nx, ny) => {
    c.moveTo(px - nx / 2 - ny / 2, py - ny / 2 + nx / 2)
    c.lineTo(px + ny / 2 - (3 * nx) / 2, py - (3 * ny) / 2 - nx / 2)
  })],
  ['cross', erMarker((c, px, py, nx, ny) => {
    c.moveTo(px - nx / 2 - ny / 2, py - ny / 2 + nx / 2)
    c.lineTo(px + ny / 2 - (3 * nx) / 2, py - (3 * ny) / 2 - nx / 2)
    c.moveTo(px - nx / 2 + ny / 2, py - ny / 2 - nx / 2)
    c.lineTo(px - ny / 2 - (3 * nx) / 2, py - (3 * ny) / 2 + nx / 2)
  })],
  ['box', (c, pe, ux, uy, size, _source, sw, filled) => {
    const nx = ux * (size + sw + 1)
    const ny = uy * (size + sw + 1)
    const px = pe.x + nx / 2
    const py = pe.y + ny / 2
    pe.x -= nx
    pe.y -= ny
    return () => {
      c.begin()
      c.moveTo(px - nx / 2 - ny / 2, py - ny / 2 + nx / 2)
      c.lineTo(px - nx / 2 + ny / 2, py - ny / 2 - nx / 2)
      c.lineTo(px + ny / 2 - (3 * nx) / 2, py - (3 * ny) / 2 - nx / 2)
      c.lineTo(px - ny / 2 - (3 * nx) / 2, py - (3 * ny) / 2 + nx / 2)
      c.close()
      finish(c, filled)
    }
  }],
  ['circle', circleMarker],
  ['circlePlus', (c, pe, ux, uy, size, source, sw, filled) => {
    const pt = { ...pe }
    const circle = circleMarker(c, pe, ux, uy, size, source, sw, filled)
    const nx = ux * (size + 2 * sw)
    const ny = uy * (size + 2 * sw)
    return () => {
      circle()
      c.begin()
      c.moveTo(pt.x - ux * sw, pt.y - uy * sw)
      c.lineTo(pt.x - 2 * nx + ux * sw, pt.y - 2 * ny + uy * sw)
      c.moveTo(pt.x - nx - ny + uy * sw, pt.y - ny + nx - ux * sw)
      c.lineTo(pt.x + ny - nx - uy * sw, pt.y - ny - nx + ux * sw)
      c.stroke()
    }
  }],
  ['halfCircle', (c, pe, ux, uy, size, _source, sw) => {
    const nx = ux * (size + sw + 1)
    const ny = uy * (size + sw + 1)
    const pt = { ...pe }
    pe.x -= nx
    pe.y -= ny
    return () => {
      c.begin()
      c.moveTo(pt.x - ny, pt.y + nx)
      c.quadTo(pe.x - ny, pe.y + nx, pe.x, pe.y)
      c.quadTo(pe.x + ny, pe.y - nx, pt.x + ny, pt.y - nx)
      c.stroke()
    }
  }],
  ['async', (c, pe, ux0, uy0, size, source, sw, filled) => {
    const ox = ux0 * sw * 1.118
    const oy = uy0 * sw * 1.118
    const ux = ux0 * (size + sw)
    const uy = uy0 * (size + sw)
    const pt = { x: pe.x - ox, y: pe.y - oy }
    pe.x += -ux - ox
    pe.y += -uy - oy
    return () => {
      c.begin()
      c.moveTo(pt.x, pt.y)
      if (source) c.lineTo(pt.x - ux - uy / 2, pt.y - uy + ux / 2)
      else c.lineTo(pt.x + uy / 2 - ux, pt.y - uy - ux / 2)
      c.lineTo(pt.x - ux, pt.y - uy)
      c.close()
      finish(c, filled)
    }
  }],
  ['openAsync', (c, pe, ux0, uy0, size, source, sw) => {
    const ux = ux0 * (size + sw)
    const uy = uy0 * (size + sw)
    const pt = { ...pe }
    return () => {
      c.begin()
      c.moveTo(pt.x, pt.y)
      if (source) c.lineTo(pt.x - ux - uy / 2, pt.y - uy + ux / 2)
      else c.lineTo(pt.x + uy / 2 - ux, pt.y - uy - ux / 2)
      c.stroke()
    }
  }],
  ['manyOptional', (c, pe, ux, uy, size, _source, sw, filled) => {
    const nx = ux * (size + sw + 1)
    const ny = uy * (size + sw + 1)
    const a = size / 2
    const px = pe.x
    const py = pe.y
    pe.x -= 2 * nx - (ux * sw) / 2
    pe.y -= 2 * ny - (uy * sw) / 2
    return () => {
      c.ellipse(px - 1.5 * nx - a, py - 1.5 * ny - a, 2 * a, 2 * a)
      finish(c, filled)
      c.begin()
      c.moveTo(px, py)
      c.lineTo(px - nx, py - ny)
      erFoot(c, px, py, nx, ny)
      c.stroke()
    }
  }],
  ['ERone', erMarker((c, px, py, nx, ny) => erBar(c, px, py, nx, ny, 0.5))],
  ['ERmandOne', erMarker((c, px, py, nx, ny) => {
    erBar(c, px, py, nx, ny, 0.5)
    erBar(c, px, py, nx, ny, 1)
  })],
  ['ERmany', erMarker(erFoot)],
  ['ERoneToMany', erMarker((c, px, py, nx, ny) => {
    erBar(c, px, py, nx, ny, 1)
    erFoot(c, px, py, nx, ny)
  })],
  ['ERzeroToOne', erZeroMarker(false)],
  ['ERzeroToMany', erZeroMarker(true)],
])

/** mxConnector.createMarker: builds the marker at one end and shortens that end of `pts` in place. */
function createMarker(c: Canvas, pts: Pt[], source: boolean, style: Style, sw: number, note: Note): (() => void) | null {
  const which = source ? 'start' : 'end'
  const type = style[`${which}Arrow`] ?? 'none'
  if (type === 'none' || type === '') return null
  const factory = MARKERS.get(type)
  if (factory === undefined) {
    note('unsupported', `${which}Arrow=${type}`, `arrowhead "${type}" is not supported; omitted`)
    return null
  }
  const n = pts.length
  const p0 = (source ? pts[1] : pts[n - 2]) as Pt
  const pe = (source ? pts[0] : pts[n - 1]) as Pt
  const dist = Math.hypot(pe.x - p0.x, pe.y - p0.y)
  if (dist === 0) return null
  const size = num(style[`${which}Size`], 6)
  return factory(c, pe, (pe.x - p0.x) / dist, (pe.y - p0.y) / dist, size, source, sw, style[`${which}Fill`] !== '0')
}

function ptSegDistSq(x1: number, y1: number, x2: number, y2: number, px: number, py: number): number {
  const dx = x2 - x1
  const dy = y2 - y1
  let qx = px - x1
  let qy = py - y1
  let dot = qx * dx + qy * dy
  let projSq: number
  if (dot <= 0) projSq = 0
  else {
    qx = dx - qx
    qy = dy - qy
    dot = qx * dx + qy * dy
    projSq = dot <= 0 ? 0 : (dot * dot) / (dx * dx + dy * dy)
  }
  return Math.max(0, qx * qx + qy * qy - projSq)
}

function ptLineDist(a: Pt, b: Pt, p: Pt): number {
  const len = Math.hypot(b.x - a.x, b.y - a.y)
  return len === 0 ? Math.hypot(p.x - a.x, p.y - a.y) : Math.abs((b.y - a.y) * p.x - (b.x - a.x) * p.y + b.x * a.y - b.y * a.x) / len
}

function segmentIntersection(p0: Pt, p1: Pt, p2: Pt, p3: Pt): Pt | null {
  const denom = (p3.y - p2.y) * (p1.x - p0.x) - (p3.x - p2.x) * (p1.y - p0.y)
  if (denom === 0) return null
  const ua = ((p3.x - p2.x) * (p0.y - p2.y) - (p3.y - p2.y) * (p0.x - p2.x)) / denom
  const ub = ((p1.x - p0.x) * (p0.y - p2.y) - (p1.y - p0.y) * (p0.x - p2.x)) / denom
  if (ua < 0 || ua > 1 || ub < 0 || ub > 1) return null
  return { x: p0.x + ua * (p1.x - p0.x), y: p0.y + ua * (p1.y - p0.y) }
}

const boxesOverlap = (a: Box, b: Box): boolean => a.x <= b.x + b.w && b.x <= a.x + a.w && a.y <= b.y + b.h && b.y <= a.y + a.h

interface RoutedPoint { x: number; y: number; jump: boolean }

/**
 * Graph.updateLineJumps: the route's points with a jump point inserted
 * wherever a segment crosses an edge drawn earlier (unless that edge has
 * noJump=1), ordered along each segment. Returns null when nothing crosses.
 */
function lineJumpPoints(pts: Pt[], others: EdgeLine[]): RoutedPoint[] | null {
  const thresh = 0.5
  const bounds = aabb(pts)
  const result: RoutedPoint[] = []
  let crossings = 0
  for (let i = 0; i < pts.length - 1; i += 1) {
    const p0 = pts[i] as Pt
    let p1 = pts[i + 1] as Pt
    let pn = pts[i + 2]
    while (i < pts.length - 2 && pn !== undefined && ptSegDistSq(p0.x, p0.y, pn.x, pn.y, p1.x, p1.y) < 1) {
      p1 = pn
      i += 1
      pn = pts[i + 2]
    }
    result.push({ x: p0.x, y: p0.y, jump: false })
    const list: Array<{ distSq: number; x: number; y: number }> = []
    for (const other of others) {
      if (!other.jumpable || !boxesOverlap(bounds, other.bounds)) continue
      const pts2 = other.pts
      let pl: Pt | null = null
      for (let j = 0; j < pts2.length - 1; j += 1) {
        const p2 = pts2[j] as Pt
        let p3 = pts2[j + 1] as Pt
        let qn = pts2[j + 2]
        while (j < pts2.length - 2 && qn !== undefined && ptSegDistSq(p2.x, p2.y, qn.x, qn.y, p3.x, p3.y) < 1) {
          p3 = qn
          j += 1
          qn = pts2[j + 2]
        }
        const pt = segmentIntersection(p0, p1, p2, p3)
        if (pt !== null
          && (Math.abs(pt.x - p0.x) > thresh || Math.abs(pt.y - p0.y) > thresh)
          && (Math.abs(pt.x - p1.x) > thresh || Math.abs(pt.y - p1.y) > thresh)
          && (pl === null || ptLineDist(p0, p1, pl) > thresh || ptLineDist(p0, p1, p2) > thresh)
          && (qn === undefined || ptLineDist(p0, p1, qn) > thresh || ptLineDist(p0, p1, p3) > thresh)) {
          const distSq = (pt.x - p0.x) ** 2 + (pt.y - p0.y) ** 2
          let idx = list.findIndex(item => item.distSq > distSq)
          if (idx === -1) idx = list.length
          const before = list[idx - 1]
          const atIdx = list[idx]
          if ((before === undefined || Math.abs(before.x - pt.x) > thresh || Math.abs(before.y - pt.y) > thresh)
            && (atIdx === undefined || Math.abs(atIdx.x - pt.x) > thresh || Math.abs(atIdx.y - pt.y) > thresh)) {
            list.splice(idx, 0, { distSq, x: pt.x, y: pt.y })
          }
        }
        pl = p2
      }
    }
    for (const item of list) result.push({ x: item.x, y: item.y, jump: true })
    crossings += list.length
  }
  const last = pts[pts.length - 1] as Pt
  result.push({ x: last.x, y: last.y, jump: false })
  return crossings > 0 ? result : null
}

/** mxConnector.paintLine with line jumps: arc, gap, sharp or line shapes of size jumpSize around each crossing. */
function paintJumpLine(c: Canvas, absPts: Pt[], routed: RoutedPoint[], rounded: boolean, arcSize: number, size: number, jumpStyle: string): void {
  let moveTo = true
  let last: Pt | null = null
  let len = 0
  let pts: Pt[] = []
  let n: Pt | null = null
  c.begin()
  for (let i = 0; i < routed.length; i += 1) {
    const rpt = routed[i] as RoutedPoint
    let pt: Pt = { x: rpt.x, y: rpt.y }
    if (i === 0) pt = absPts[0] as Pt
    else if (i === routed.length - 1) pt = absPts[absPts.length - 1] as Pt
    let done = false
    if (last !== null && rpt.jump) {
      const next = routed[i + 1] as RoutedPoint
      if (n === null) {
        len = Math.hypot(pt.x - last.x, pt.y - last.y)
        n = len > 0 ? { x: ((pt.x - last.x) * size) / len, y: ((pt.y - last.y) * size) / len } : null
      }
      const ahead = (next.x - pt.x) ** 2 + (next.y - pt.y) ** 2
      const behind = (last.x - pt.x) ** 2 + (last.y - pt.y) ** 2
      if (n !== null && ahead > size * size && len > 0 && behind > size * size) {
        const p0 = { x: pt.x - n.x, y: pt.y - n.y }
        const p1 = { x: pt.x + n.x, y: pt.y + n.y }
        pts.push(p0)
        addPoints(c, pts, rounded, arcSize, false, null, moveTo)
        let f = Math.round(n.x) < 0 || (Math.round(n.x) === 0 && Math.round(n.y) <= 0) ? 1 : -1
        moveTo = false
        if (jumpStyle === 'sharp') {
          c.lineTo(p0.x - n.y * f, p0.y + n.x * f)
          c.lineTo(p1.x - n.y * f, p1.y + n.x * f)
          c.lineTo(p1.x, p1.y)
        } else if (jumpStyle === 'line') {
          c.moveTo(p0.x + n.y * f, p0.y - n.x * f)
          c.lineTo(p0.x - n.y * f, p0.y + n.x * f)
          c.moveTo(p1.x - n.y * f, p1.y + n.x * f)
          c.lineTo(p1.x + n.y * f, p1.y - n.x * f)
          c.moveTo(p1.x, p1.y)
        } else if (jumpStyle === 'arc') {
          f *= 1.3
          c.curveTo(p0.x - n.y * f, p0.y + n.x * f, p1.x - n.y * f, p1.y + n.x * f, p1.x, p1.y)
        } else {
          c.moveTo(p1.x, p1.y)
          moveTo = true
        }
        pts = [p1]
        done = true
      }
    } else {
      n = null
    }
    if (!done) {
      pts.push(pt)
      last = pt
    }
  }
  addPoints(c, pts, rounded, arcSize, false, null, moveTo)
  c.stroke()
}

function paintCurvedLine(c: Canvas, pts: Pt[]): void {
  const n = pts.length
  c.begin()
  c.moveTo((pts[0] as Pt).x, (pts[0] as Pt).y)
  for (let i = 1; i < n - 2; i += 1) {
    const p0 = pts[i] as Pt
    const p1 = pts[i + 1] as Pt
    c.quadTo(p0.x, p0.y, (p0.x + p1.x) / 2, (p0.y + p1.y) / 2)
  }
  const p0 = pts[n - 2] as Pt
  const p1 = pts[n - 1] as Pt
  c.quadTo(p0.x, p0.y, p1.x, p1.y)
  c.stroke()
}

/** mxArrowConnector.getCurvePoints: flatten a curved route into quadratic segments. */
function curvePoints(pts: Pt[]): Pt[] {
  const result = [pts[0] as Pt]
  const n = pts.length
  let p0 = pts[0] as Pt
  for (let i = 1; i < n - 1; i += 1) {
    const pc = pts[i] as Pt
    const pe = i < n - 2 ? { x: (pc.x + (pts[i + 1] as Pt).x) / 2, y: (pc.y + (pts[i + 1] as Pt).y) / 2 } : (pts[i + 1] as Pt)
    const len = Math.hypot(pc.x - p0.x, pc.y - p0.y) + Math.hypot(pe.x - pc.x, pe.y - pc.y)
    const steps = Math.max(4, Math.min(Math.ceil(len / 8), 64))
    for (let j = 1; j <= steps; j += 1) {
      const u = j / steps
      const iu = 1 - u
      result.push({ x: iu * iu * p0.x + 2 * iu * u * pc.x + u * u * pe.x, y: iu * iu * p0.y + 2 * iu * u * pc.y + u * u * pe.y })
    }
    p0 = pe
  }
  return result
}

/** mxArrowConnector.trimCurveForMarker: cut a flattened curve where it is `dist` from the end. */
function trimCurve(pts: Pt[], dist: number, source: boolean): Pt[] {
  const n = pts.length
  const pc = (source ? pts[0] : pts[n - 1]) as Pt
  const cut = (p0: Pt, p1: Pt): Pt => {
    const dx = p1.x - p0.x
    const dy = p1.y - p0.y
    const fx = p0.x - pc.x
    const fy = p0.y - pc.y
    const a = dx * dx + dy * dy
    const b = 2 * (fx * dx + fy * dy)
    const cc = fx * fx + fy * fy - dist * dist
    const disc = b * b - 4 * a * cc
    if (a === 0 || disc < 0) return p0
    const t = clamp((-b - Math.sqrt(disc)) / (2 * a), 0, 1)
    return { x: p0.x + t * dx, y: p0.y + t * dy }
  }
  if (source) {
    for (let i = 1; i < n - 1; i += 1) {
      const p = pts[i] as Pt
      if ((p.x - pc.x) ** 2 + (p.y - pc.y) ** 2 >= dist * dist) return [pc, cut(p, pts[i - 1] as Pt), ...pts.slice(i)]
    }
  } else {
    for (let i = n - 2; i > 0; i -= 1) {
      const p = pts[i] as Pt
      if ((p.x - pc.x) ** 2 + (p.y - pc.y) ** 2 >= dist * dist) return [...pts.slice(0, i + 1), cut(p, pts[i + 1] as Pt), pc]
    }
  }
  return pts
}

function relativeCcw(a: Pt, b: Pt, p: Pt): number {
  const x2 = b.x - a.x
  const y2 = b.y - a.y
  let px = p.x - a.x
  let py = p.y - a.y
  let ccw = px * y2 - py * x2
  if (ccw === 0) {
    ccw = px * x2 + py * y2
    if (ccw > 0) {
      px -= x2
      py -= y2
      ccw = px * x2 + py * y2
      if (ccw < 0) ccw = 0
    }
  }
  return ccw < 0 ? -1 : ccw > 0 ? 1 : 0
}

function arrowConnectorHead(c: Canvas, x: number, y: number, nx: number, ny: number, size: number, arrowWidth: number, edgeWidth: number, spacing: number, initialMove: boolean): void {
  const ratio = edgeWidth / arrowWidth
  const ox = (edgeWidth * ny) / 2
  const oy = (-edgeWidth * nx) / 2
  const sx = (spacing + size) * nx
  const sy = (spacing + size) * ny
  if (initialMove) c.moveTo(x - ox + sx, y - oy + sy)
  else c.lineTo(x - ox + sx, y - oy + sy)
  c.lineTo(x - ox / ratio + sx, y - oy / ratio + sy)
  c.lineTo(x + spacing * nx, y + spacing * ny)
  c.lineTo(x + ox / ratio + sx, y + oy / ratio + sy)
  c.lineTo(x + ox + sx, y + oy + sy)
}

/**
 * mxArrowConnector.paintEdgeShape for `flexArrow` (a filled band with
 * arrowheads) and `link` (two parallel open lines): offset the route by half
 * the band width on each side, mitring or rounding the joins, then close the
 * band through the arrowheads.
 */
function paintArrowConnector(c: Canvas, input: Pt[], style: Style, sw: number, link: boolean): void {
  const curved = style.curved === '1' && input.length > 2
  let pts = curved ? curvePoints(input) : input
  const edgeWidth = num(style.width, link ? 4 : 10) + Math.max(0, sw - 1)
  const startWidth = (link ? 30 : edgeWidth + num(style.startWidth, 20)) + sw
  const endWidth = (link ? 30 : edgeWidth + num(style.endWidth, 20)) + sw
  const markerStart = (style.startArrow ?? 'none') !== 'none'
  const markerEnd = (style.endArrow ?? 'none') !== 'none'
  const spacing = link ? 0 : sw / 2
  const startSize = num(style.startSize, 6) * 3 + sw
  const endSize = num(style.endSize, 6) * 3 + sw
  const rounded = !curved && style.rounded === '1'
  if (curved && !link) {
    if (markerStart) pts = trimCurve(pts, spacing + startSize, true)
    if (markerEnd) pts = trimCurve(pts, spacing + endSize, false)
  }
  const first = pts[0] as Pt
  const second = pts[1] as Pt
  const pe = pts[pts.length - 1] as Pt
  const dist = Math.hypot(second.x - first.x, second.y - first.y)
  if (dist === 0) return
  let nx = (second.x - first.x) / dist
  let ny = (second.y - first.y) / dist
  let nx1 = nx
  let ny1 = ny
  let orthx = edgeWidth * ny
  let orthy = -edgeWidth * nx
  const fns: Array<() => void> = []
  if (rounded) c.setLineJoin('round')
  else if (pts.length > 2) c.setMiterLimit(1.42)
  c.begin()
  const startNx = nx
  const startNy = ny
  if (markerStart && !link) arrowConnectorHead(c, first.x, first.y, nx, ny, startSize, startWidth, edgeWidth, spacing, true)
  else {
    const outX = first.x + orthx / 2 + spacing * nx
    const outY = first.y + orthy / 2 + spacing * ny
    const inX = first.x - orthx / 2 + spacing * nx
    const inY = first.y - orthy / 2 + spacing * ny
    if (link) {
      c.moveTo(outX, outY)
      fns.push(() => c.lineTo(inX, inY))
    } else {
      c.moveTo(inX, inY)
      c.lineTo(outX, outY)
    }
  }
  for (let i = 0; i < pts.length - 2; i += 1) {
    const a = pts[i] as Pt
    const b = pts[i + 1] as Pt
    const d = pts[i + 2] as Pt
    const pos = relativeCcw(a, b, d)
    const dist1 = Math.hypot(d.x - b.x, d.y - b.y)
    if (dist1 === 0) continue
    nx1 = (d.x - b.x) / dist1
    ny1 = (d.y - b.y) / dist1
    const tmp = Math.max(Math.sqrt((nx * nx1 + ny * ny1 + 1) / 2), 0.04)
    let nx2 = nx + nx1
    let ny2 = ny + ny1
    const dist2 = Math.hypot(nx2, ny2)
    if (dist2 === 0) continue
    nx2 /= dist2
    ny2 /= dist2
    const swFactor = Math.max(tmp, Math.min(sw / 200 + 0.04, 0.35))
    const angleFactor = pos !== 0 && rounded ? Math.max(0.1, swFactor) : Math.max(tmp, 0.06)
    const outX = b.x + (ny2 * edgeWidth) / 2 / angleFactor
    const outY = b.y - (nx2 * edgeWidth) / 2 / angleFactor
    const inX = b.x - (ny2 * edgeWidth) / 2 / angleFactor
    const inY = b.y + (nx2 * edgeWidth) / 2 / angleFactor
    if (pos === 0 || !rounded) {
      c.lineTo(outX, outY)
      fns.push(() => c.lineTo(inX, inY))
    } else if (pos === -1) {
      c.lineTo(inX + ny * edgeWidth, inY - nx * edgeWidth)
      c.quadTo(outX, outY, inX + ny1 * edgeWidth, inY - nx1 * edgeWidth)
      fns.push(() => c.lineTo(inX, inY))
    } else {
      c.lineTo(outX, outY)
      const c1x = outX - ny * edgeWidth
      const c1y = outY + nx * edgeWidth
      const c2x = outX - ny1 * edgeWidth
      const c2y = outY + nx1 * edgeWidth
      fns.push(() => c.quadTo(inX, inY, c1x, c1y))
      fns.push(() => c.lineTo(c2x, c2y))
    }
    nx = nx1
    ny = ny1
  }
  orthx = edgeWidth * ny1
  orthy = -edgeWidth * nx1
  if (markerEnd && !link) arrowConnectorHead(c, pe.x, pe.y, -nx, -ny, endSize, endWidth, edgeWidth, spacing, false)
  else {
    c.lineTo(pe.x - spacing * nx1 + orthx / 2, pe.y - spacing * ny1 + orthy / 2)
    const inX = pe.x - spacing * nx1 - orthx / 2
    const inY = pe.y - spacing * ny1 - orthy / 2
    if (!link) c.lineTo(inX, inY)
    else {
      c.moveTo(inX, inY)
      fns.splice(0, 0, () => c.moveTo(inX, inY))
    }
  }
  for (let i = fns.length - 1; i >= 0; i -= 1) fns[i]?.()
  if (link) c.stroke()
  else {
    c.close()
    c.fillAndStroke()
  }
  c.setMiterLimit(10)
  c.setLineJoin('miter')
  if (pts.length > 2 && !link) {
    if (markerStart) {
      c.begin()
      arrowConnectorHead(c, first.x, first.y, startNx, startNy, startSize, startWidth, edgeWidth, spacing, true)
      c.stroke()
    }
    if (markerEnd) {
      c.begin()
      arrowConnectorHead(c, pe.x, pe.y, -nx, -ny, endSize, endWidth, edgeWidth, spacing, true)
      c.stroke()
    }
  }
}

/** mxGraphView.getPoint: point at `fraction` of the route's length, moved `normal` px to the left of the direction of travel. */
function pointAlong(points: Pt[], fraction: number, normal: number): Pt {
  const lengths = points.slice(1).map((p, i) => Math.hypot(p.x - (points[i] as Pt).x, p.y - (points[i] as Pt).y))
  const total = lengths.reduce((a, b) => a + b, 0)
  let remaining = clamp(fraction, 0, 1) * total
  for (let i = 0; i < lengths.length; i += 1) {
    const len = lengths[i] as number
    if (remaining <= len || i === lengths.length - 1) {
      const a = points[i] as Pt
      const b = points[i + 1] as Pt
      const t = len === 0 ? 0 : Math.min(1, remaining / len)
      const ux = len === 0 ? 0 : (b.x - a.x) / len
      const uy = len === 0 ? 0 : (b.y - a.y) / len
      return { x: a.x + (b.x - a.x) * t + uy * normal, y: a.y + (b.y - a.y) * t - ux * normal }
    }
    remaining -= len
  }
  return points[0] ?? { x: 0, y: 0 }
}

function renderEdgeLabel(ctx: Context, owner: Cell, geometry: Geometry | null, points: Pt[], note: Note): void {
  const style = owner.style
  const fraction = geometry !== null && geometry.relative ? (geometry.x + 1) / 2 : 0.5
  const normal = geometry !== null && geometry.relative ? geometry.y : 0
  const at = pointAlong(points, fraction, normal)
  const p = { x: at.x + (geometry?.offset?.x ?? 0), y: at.y + (geometry?.offset?.y ?? 0) }
  const base = fontFromStyle(style, cellColor(owner, 'fontColor', '#000000', note))
  const parsed = parseLabel(owner.label, style, base, note)
  renderText(ctx, {
    lines: parsed.lines,
    spaceAfter: parsed.spaceAfter,
    base,
    box: { x: p.x, y: p.y, w: 0, h: 0 },
    align: enumValue<HAlign>(style, 'align', H_ALIGNS, 'center', note),
    valign: enumValue<VAlign>(style, 'verticalAlign', V_ALIGNS, 'middle', note),
    wrap: false,
    transform: IDENTITY,
    background: optionalColor(style.labelBackgroundColor, '#ffffff', 'labelBackgroundColor', note),
    border: optionalColor(style.labelBorderColor, '#000000', 'labelBorderColor', note),
    opacity: num(style.textOpacity, 100),
    preserveSpace: !parsed.html,
    overflow: 'visible',
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

/** A frame whose perimeter is grown by `border` px on every side (perimeterSpacing). */
function grownFrame(frame: Frame, border: number): Frame {
  if (border === 0 || frame.centerOnly) return frame
  const b = frame.bounds
  const c = frame.center
  const sx = b.w > 0 ? (b.w + 2 * border) / b.w : 1
  const sy = b.h > 0 ? (b.h + 2 * border) / b.h : 1
  return {
    ...frame,
    outline: frame.outline.map(p => ({ x: c.x + (p.x - c.x) * sx, y: c.y + (p.y - c.y) * sy })),
    bounds: { x: b.x - border, y: b.y - border, w: b.w + 2 * border, h: b.h + 2 * border },
  }
}

const EDGE_SHAPES = new Set(SUPPORTED_EDGE_SHAPES)
const JUMP_STYLES = new Set(['arc', 'gap', 'sharp', 'line'])

/**
 * Route and draw one edge, then its own label and any label cells.
 *
 * Steps: resolve both terminals and grow floating ones by the perimeter
 * spacing; route by edgeStyle; build arrowheads at the route ends, which
 * shortens the line beneath them; add jumps over earlier edges; paint the
 * line (or a flexArrow / link band), the heads and the labels.
 */
function renderEdge(ctx: Context, cell: Cell, cells: Map<string, Cell>, boxes: Map<string, Box | null>): void {
  const note = ctx.note(cell.id)
  const style = cell.style
  const g = cell.geometry
  const origin = originOf(cell, boxes)
  const shift = (p: Pt): Pt => ({ x: p.x + origin.x, y: p.y + origin.y })
  const waypoints = (g?.points ?? []).map(shift)
  const srcT = resolveTerminal(ctx, cell.sourceId, g?.sourcePoint ? shift(g.sourcePoint) : null, cells, note)
  const tgtT = resolveTerminal(ctx, cell.targetId, g?.targetPoint ? shift(g.targetPoint) : null, cells, note)
  if (srcT === 'hidden' || tgtT === 'hidden') return
  if ((srcT.frame === null && srcT.point === null) || (tgtT.frame === null && tgtT.point === null)) {
    note('unsupported', 'edge:dangling', 'edge has no usable source or target; not drawn')
    return
  }
  const spacing = num(style.perimeterSpacing, 0)
  const grow = (t: Terminal, key: string): Terminal =>
    (t.frame === null ? t : { frame: grownFrame(t.frame, spacing + num(style[key], 0) + num(t.frame.style.perimeterSpacing, 0)), point: t.point })
  const src = grow(srcT, 'sourcePerimeterSpacing')
  const tgt = grow(tgtT, 'targetPerimeterSpacing')

  const shapeName = style.shape ?? 'connector'
  if (!EDGE_SHAPES.has(shapeName)) {
    note('unsupported', `shape=${shapeName}`, `edge shape "${shapeName}" is not supported; drawn as a plain connector`)
  }
  const edgeStyle = style.edgeStyle === undefined || style.edgeStyle === '' ? 'none' : style.edgeStyle
  if (!EDGE_STYLE_SET.has(edgeStyle)) note('approximated', `edgeStyle=${edgeStyle}`, `edgeStyle "${edgeStyle}" is not supported; routed as a straight line`)
  const srcPort = srcT.frame === null ? null : constraintPort(srcT.frame, style, 'exit')
  const tgtPort = tgtT.frame === null ? null : constraintPort(tgtT.frame, style, 'entry')
  const fixedOf = (t: Terminal, port: Port | null): Pt | null => port?.pt ?? t.point
  const boxOf = (t: Terminal): Box => t.frame?.bounds ?? { x: t.point?.x ?? 0, y: t.point?.y ?? 0, w: 0, h: 0 }
  const centreOf = (t: Terminal): Pt => fixedOf(t, null) ?? t.frame?.center ?? { x: 0, y: 0 }
  const looseDir = (from: Pt, to: Pt): Pt => snapDir({ x: to.x - from.x, y: to.y - from.y })

  let points: Pt[]
  if (srcT.frame !== null && srcT.frame === tgtT.frame && waypoints.length === 0) {
    note('approximated', 'edge:loop', 'self-loop drawn as a fixed loop on the right side')
    const b = srcT.frame.bounds
    const c = srcT.frame.center
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

  const stroke = cellColor(cell, 'strokeColor', '#000000', note)
  const sw = Math.max(0, num(style.strokeWidth, 1))
  const c = canvasFor(style, 'none', stroke, sw)
  let extent = 0
  if (shapeName === 'flexArrow' || shapeName === 'link') {
    c.setFillColor(cellColor(cell, 'fillColor', '#ffffff', note, true))
    paintArrowConnector(c, points, style, sw, shapeName === 'link')
    extent = Math.max(num(style.width, 10), num(style.startWidth, 20), num(style.endWidth, 20)) + sw * 2
  } else {
    const line = points.map(p => ({ ...p }))
    const startMarker = createMarker(c, line, true, style, sw, note)
    const endMarker = createMarker(c, line, false, style, sw, note)
    const rounded = style.rounded === '1'
    const arcSize = num(style.arcSize, 20) / 2
    const jumpStyle = style.jumpStyle ?? 'none'
    if (jumpStyle !== 'none' && !JUMP_STYLES.has(jumpStyle)) note('approximated', `jumpStyle=${jumpStyle}`, `jumpStyle "${jumpStyle}" is not supported; no jumps drawn`)
    const routed = JUMP_STYLES.has(jumpStyle) && style.curved !== '1' ? lineJumpPoints(points, ctx.edgeLines) : null
    if (JUMP_STYLES.has(jumpStyle) && style.curved === '1') note('approximated', 'jumpStyle:curved', 'line jumps on curved edges are not drawn')
    if (style.curved === '1' && line.length > 2) paintCurvedLine(c, line)
    else if (routed !== null) paintJumpLine(c, line, routed, rounded, arcSize, (num(style.jumpSize, 6) - 2) / 2 + sw, jumpStyle)
    else {
      c.begin()
      addPoints(c, line, rounded, arcSize, false)
      c.stroke()
    }
    c.setDashed(false)
    const startStroke = style.startStrokeColor === undefined ? null : resolveColor(style.startStrokeColor, stroke, 'startStrokeColor', note)
    if (startMarker !== null) {
      c.setFillColor(resolveColor(style.startFillColor, stroke, 'startFillColor', note))
      if (startStroke !== null) c.setStrokeColor(startStroke)
      startMarker()
    }
    if (endMarker !== null) {
      c.setFillColor(resolveColor(style.endFillColor, stroke, 'endFillColor', note))
      if (style.endStrokeColor !== undefined) c.setStrokeColor(resolveColor(style.endStrokeColor, stroke, 'endStrokeColor', note))
      else if (startStroke !== null) c.setStrokeColor(stroke)
      endMarker()
    }
    extent = (Math.max(num(style.startSize, 6), num(style.endSize, 6)) + sw + 1) * 2.5
  }
  const routeBounds = aabb(points)
  const region = { x: routeBounds.x - extent, y: routeBounds.y - extent, w: routeBounds.w + 2 * extent, h: routeBounds.h + 2 * extent }
  const opacity = num(style.opacity, 100)
  const attrs = (opacity < 100 ? ` opacity="${fmt(Math.max(0, opacity) / 100)}"` : '') + ctx.shadow(style, region, note)
  ctx.body.push(attrs === '' ? c.parts.join('') : `<g${attrs}>${c.parts.join('')}</g>`)
  ctx.bounds.addBox(region)
  ctx.edgeLines.push({ pts: points, bounds: routeBounds, jumpable: style.noJump !== '1' })
  ctx.drawn += 1

  if (cell.label !== '' && style.noLabel !== '1') renderEdgeLabel(ctx, cell, g, points, note)
  for (const child of cell.children) {
    if (!child.vertex || !child.visible || child.label === '' || child.style.noLabel === '1') continue
    renderEdgeLabel(ctx, child, child.geometry, points, ctx.note(child.id))
  }
}

/* ================================================================== *
 * Page assembly
 * ================================================================== */

/**
 * Render one page. Pass 1 computes every vertex frame so edges can attach to
 * cells that appear later in the document. Pass 2 walks the cell tree depth
 * first in document order, drawing each cell before its children, which is
 * draw.io's z-order; table grid lines follow a table's rows. Collapsed cells
 * hide their children; invisible cells hide their subtree.
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
    const frame = cell.vertex ? ctx.frames.get(cell.id) ?? null : null
    if (frame !== null) renderVertex(ctx, cell, frame, ctx.note(cell.id))
    if (cell.vertex && cell.collapsed) return
    cell.children.forEach(draw)
    if (frame !== null && frame.kind === 'table') renderTableLines(ctx, cell, frame, ctx.note(cell.id))
  }
  roots.forEach(draw)

  const padding = Math.max(0, options.padding ?? 10)
  const b = ctx.bounds.empty ? { x: 0, y: 0, w: 0, h: 0 } : { x: ctx.bounds.minX, y: ctx.bounds.minY, w: ctx.bounds.maxX - ctx.bounds.minX, h: ctx.bounds.maxY - ctx.bounds.minY }
  const x = Math.floor(b.x - padding)
  const y = Math.floor(b.y - padding)
  const width = Math.ceil(b.x + b.w + padding) - x
  const height = Math.ceil(b.y + b.h + padding) - y

  const parts = [`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="${width}" height="${height}" viewBox="${x} ${y} ${width} ${height}" stroke-miterlimit="10">`]
  if (ctx.defs.length > 0) parts.push(`<defs>${ctx.defs.join('')}</defs>`)
  const background = resolveColor(page.model.attrs.background, 'none', 'background', ctx.note(null))
  if (options.background !== false && background !== 'none') {
    parts.push(`<rect x="${x}" y="${y}" width="${width}" height="${height}" fill="${esc(background)}"/>`)
  }
  parts.push(...ctx.body, '</svg>')

  ctx.diagnostics.sort((a, b2) => (a.severity === b2.severity ? 0 : a.severity === 'unsupported' ? -1 : 1))
  const fidelity: Fidelity = ctx.drawn === 0 ? 'none' : ctx.diagnostics.length === 0 ? 'full' : 'partial'
  return { name: page.name, id: page.id, svg: parts.join(''), width, height, fidelity, diagnostics: ctx.diagnostics }
}
