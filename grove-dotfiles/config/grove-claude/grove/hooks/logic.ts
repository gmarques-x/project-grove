// Pure helpers for the grove mod: no `$`, so tests can call them directly.

import type { GroveAgentStatus, GrovePalette } from '../types'

/** Dark Medium, built in: used when grove's state or palette file is missing. */
export const FALLBACK: GrovePalette = {
  scheme: 'dark-medium',
  green: '#A7C080',
  yellow: '#DBBC7F',
  red: '#E67E80',
  aqua: '#83C092',
  blue: '#7FBBB3',
  orange: '#E69875',
  fg: '#D3C6AA',
  dim: '#859289',
  muted: '#9DA9A0',
  track: '#475258',
  bg: '#2D353B',
}

const HEX = /^#[0-9A-Fa-f]{6}$/

/** Reads a grove palette file (`name = #RRGGBB` lines) into the pane's roles. */
export function parsePalette(text: string, scheme: string): GrovePalette {
  const named: Record<string, string> = {}
  for (const raw of text.split('\n')) {
    const m = /^([a-z_0-9]+)\s*=\s*(#[0-9A-Fa-f]{6})\b/.exec(raw.trim())
    const [, name, hex] = m ?? []
    if (!name || !hex) continue
    named[name] = hex.toUpperCase()
  }
  const pick = (...names: string[]): string | undefined =>
    names.map(n => named[n]).find(v => v !== undefined && HEX.test(v))
  const palette: GrovePalette = {
    scheme,
    green: pick('green') ?? FALLBACK.green,
    yellow: pick('yellow') ?? FALLBACK.yellow,
    red: pick('red') ?? FALLBACK.red,
    aqua: pick('aqua') ?? FALLBACK.aqua,
    blue: pick('blue') ?? FALLBACK.blue,
    orange: pick('orange') ?? FALLBACK.orange,
    fg: pick('fg') ?? FALLBACK.fg,
    dim: pick('dim', 'grey1') ?? FALLBACK.dim,
    muted: pick('muted', 'grey2') ?? FALLBACK.muted,
    track: pick('border', 'bg3') ?? FALLBACK.track,
    bg: pick('bg0') ?? FALLBACK.bg,
  }
  return palette
}

/** A scheme name as grove stores it: `dark-medium`, `light-soft`, ... */
export function cleanScheme(text: string): string | undefined {
  const s = text.trim()
  return /^(dark|light)-(hard|medium|soft)$/.test(s) ? s : undefined
}

const base = (p: unknown): string =>
  typeof p === 'string' ? (p.split('/').filter(Boolean).pop() ?? p) : ''

const str = (v: unknown): string => (typeof v === 'string' ? v : '')

const clip = (s: string, n: number): string =>
  s.length > n ? `${s.slice(0, n - 1)}…` : s

/** What a tool call is doing, in a few words, for the pane's "now" column. */
export function describeCall(tool: string, input: Record<string, unknown>): string {
  switch (tool) {
    case 'Read':
      return `reading ${base(input.file_path)}`
    case 'Edit':
    case 'MultiEdit':
      return `editing ${base(input.file_path)}`
    case 'Write':
      return `writing ${base(input.file_path)}`
    case 'NotebookEdit':
      return `editing ${base(input.notebook_path)}`
    case 'Bash': {
      const what = str(input.description) || str(input.command)
      return `running: ${clip(what.split('\n')[0] ?? '', 40)}`
    }
    case 'Grep':
      return `searching '${clip(str(input.pattern), 30)}'`
    case 'Glob':
      return `finding ${clip(str(input.pattern), 30)}`
    case 'WebFetch': {
      const url = str(input.url)
      const host = /^[a-z]+:\/\/([^/]+)/i.exec(url)?.[1] ?? url
      return `fetching ${host}`
    }
    case 'WebSearch':
      return `searching the web`
    case 'Agent':
      return `starting an agent`
    case 'TaskCreate':
    case 'TaskUpdate':
    case 'TaskList':
    case 'TaskGet':
      return 'updating tasks'
    default:
      if (tool.startsWith('mcp__')) {
        const parts = tool.split('__')
        return `${parts[1] ?? 'mcp'}: ${parts.slice(2).join('_')}`
      }
      return tool
  }
}

/** A workflow's name, from the Workflow call's input. */
export function workflowName(input: Record<string, unknown>): string {
  const named = str(input.name)
  if (named) return named
  const m = /name\s*:\s*['"]([^'"]+)['"]/.exec(str(input.script))
  if (m?.[1]) return m[1]
  const path = base(input.scriptPath)
  return path ? path.replace(/\.[a-z]+$/i, '') : 'workflow'
}

export function firstLine(text: string): string {
  return (
    text
      .split('\n')
      .map(l => l.replace(/^[#>*\-\s]+/, '').trim())
      .find(l => l.length > 0) ?? ''
  )
}

/** `0:42`, `12:05`, `1:02:03` */
export function formatElapsed(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const ss = String(s % 60).padStart(2, '0')
  return h > 0 ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`
}

/** `$.agent.list()` status to the pane's. */
export function fromListStatus(s: string): GroveAgentStatus | undefined {
  switch (s) {
    case 'pending':
    case 'running':
    case 'waiting':
      return 'running'
    case 'idle':
      return 'idle'
    case 'completed':
      return 'done'
    case 'failed':
      return 'failed'
    case 'killed':
      return 'stopped'
    default:
      return undefined
  }
}

export const MAX_ROWS = 30

/** Keeps at most MAX_ROWS rows, dropping the oldest finished ones first. */
export function capRows<T extends { status: GroveAgentStatus }>(rows: T[]): T[] {
  const out = [...rows]
  while (out.length > MAX_ROWS) {
    const i = out.findIndex(r => r.status === 'done' || r.status === 'failed' || r.status === 'stopped')
    out.splice(i === -1 ? 0 : i, 1)
  }
  return out
}

// ── models ───────────────────────────────────────────────────────────────

/** `claude-opus-5-5[1m]` → `Opus 5.5 (1M)`, `claude-haiku-5-5` → `Haiku 5.5`, `haiku` → `Haiku`. */
export function modelName(id: string | undefined): string {
  if (!id) return '?'
  const long = /\[1m\]/i.test(id) ? ' (1M)' : ''
  const bare = id.replace(/\[[^\]]*\]/g, '').replace(/^(us|eu|apac|global)\.anthropic\./, '').replace(/-v\d+(:\d+)?$/, '')
  const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)
  const m = /^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$/.exec(bare)
  if (m) return `${cap(m[1] ?? '')} ${m[2]}${m[3] ? `.${m[3]}` : ''}${long}`
  const old = /^claude-(\d+)(?:-(\d))?-([a-z]+)/.exec(bare)
  if (old) return `${cap(old[3] ?? '')} ${old[1]}${old[2] ? `.${old[2]}` : ''}${long}`
  if (/^[a-z]+$/.test(bare)) return cap(bare) + long
  return bare + long
}

// ── what kind of task an agent is on ─────────────────────────────────────

export type TaskKind = 'research' | 'coding' | 'testing' | 'review' | 'planning' | 'ops' | 'writing'

const KIND_WORDS: Array<[TaskKind, RegExp]> = [
  ['testing', /\b(tests?|testing|bats|tdd|verify|verification|qa|regression)\b/],
  ['review', /\b(review|audit|critique|inspect)\b/],
  ['coding', /\b(implement|fix|build|refactor|add|edit|code|create|migrate|port|rewrite|patch)\b/],
  ['planning', /\b(plan|design|architect|spec|outline)\b/],
  ['ops', /\b(deploy|install|ssh|configure|release|provision|restart|upgrade)\b/],
  ['writing', /\b(docs?|readme|write[- ]up|summari[sz]e|draft)\b/],
  ['research', /\b(find|search|survey|list|explain|explore|investigate|look|map|research|read)\b/],
]

/** A first guess from the agent's type and its task, before it does anything. */
export function kindAtStart(type: string, description: string, prompt: string): TaskKind {
  const t = type.toLowerCase()
  if (t === 'explore') return 'research'
  if (t === 'plan') return 'planning'
  if (/review/.test(t)) return 'review'
  if (/test/.test(t)) return 'testing'
  for (const text of [description, prompt]) {
    const s = text.toLowerCase()
    const hit = KIND_WORDS.find(([, re]) => re.test(s))
    if (hit) return hit[0]
  }
  return 'research'
}

const TEST_RUN = /\b(bats|pytest|jest|vitest|mocha|go test|cargo test|swift test|xcodebuild test|npm (run )?test|pnpm test|yarn test|plugin test|rspec|phpunit)\b/
const TEST_FILE = /(\.test\.|\.spec\.|_test\.|\.bats$|\/tests?\/)/

/** What a tool call says about the kind: edits make research into coding, test runs make it testing. */
export function kindAfterCall(kind: TaskKind, tool: string, input: Record<string, unknown>): TaskKind {
  const path = typeof input.file_path === 'string' ? input.file_path : typeof input.notebook_path === 'string' ? input.notebook_path : ''
  if (tool === 'Edit' || tool === 'Write' || tool === 'MultiEdit' || tool === 'NotebookEdit') {
    if (TEST_FILE.test(path) && (kind === 'research' || kind === 'coding')) return 'testing'
    if (kind === 'research' || kind === 'planning') return 'coding'
    return kind
  }
  if (tool === 'Bash' && typeof input.command === 'string' && TEST_RUN.test(input.command)) {
    if (kind === 'research' || kind === 'coding') return 'testing'
  }
  return kind
}

// ── usage ────────────────────────────────────────────────────────────────

/** A rate-limit window's row label: `five_hour` → session, `seven_day` → week, a model's own → its name. */
export function windowLabel(kind: string): string {
  const k = kind.toLowerCase()
  for (const m of ['fable', 'opus', 'sonnet', 'haiku']) if (k.includes(m)) return m
  if (k === 'five_hour' || k.startsWith('five_hour')) return 'session'
  if (k === 'seven_day') return 'week'
  if (k.includes('spend')) return 'spend'
  return k.replace(/_/g, ' ')
}

/** `resets 15:40` today, else `resets Thu 09:00`. */
export function resetText(iso: string | undefined, now: number): string {
  if (!iso) return ''
  const at = new Date(iso)
  if (Number.isNaN(at.getTime())) return ''
  const hm = `${String(at.getHours()).padStart(2, '0')}:${String(at.getMinutes()).padStart(2, '0')}`
  if (at.getTime() - now < 20 * 3600_000) return `resets ${hm}`
  const day = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][at.getDay()]
  return `resets ${day} ${hm}`
}
