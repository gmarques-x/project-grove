// The Grove MOTD look (grove-lab's /etc/update-motd.d/10-grove), for the
// Agents pane: a seasonal pixel grove that changes every hour, 6-wide labels,
// ━ bars and a line of wisdom. Pure: lines of colored segments, no `$`.
//
// Colors: the seasonal leaf, particle and accent colors and the trunk and
// ground below are the MOTD's own, not Everforest, on purpose (the owner's
// choice, like the fastfetch art): tests/theme.bats leaves this file out.
// Every other color the pane draws comes from the scheme's palette at run time.

import type { GroveAgent, GrovePalette, GroveTask, GroveUsage } from '../types'
import { formatElapsed, modelName, resetText, windowLabel } from './logic'

/** One run of text in one style. */
export type Seg = { t: string; c?: string; b?: boolean; i?: boolean }
export type Line = Seg[]

export type Season = 'spring' | 'summer' | 'autumn' | 'winter'

type SeasonLook = {
  leaf: string[]
  particle: string[]
  chars: string[]
  /** % chance a blank cell holds a particle. */
  part: number
  /** Rows (of the MOTD's 8) above which no particle falls. */
  prow: number
  accent: string
}

// The MOTD's own seasonal colors, copied as they are.
const SEASONS: Record<Season, SeasonLook> = {
  spring: {
    leaf: ['#6A994E', '#90BE6D', '#A7C957', '#F4ACB7', '#FFC8DD'],
    particle: ['#F4ACB7', '#FFD6E0'],
    chars: ['·', '*', '✿'],
    part: 3,
    prow: 0,
    accent: '#A7C957',
  },
  summer: {
    leaf: ['#1B4332', '#2D6A4F', '#40916C', '#52B788', '#74C69D'],
    particle: ['#F9E79F', '#FFF3B0'],
    chars: ['·', '✿'],
    part: 2,
    prow: 0,
    accent: '#52B788',
  },
  autumn: {
    leaf: ['#9E2A2B', '#BC4B2A', '#D9732B', '#F2A541', '#E9C46A'],
    particle: ['#D9732B', '#F2A541', '#BC4B2A'],
    chars: [',', "'", '·', '`'],
    part: 6,
    prow: 4,
    accent: '#F2A541',
  },
  winter: {
    leaf: ['#F1F5F8', '#D6E2EA', '#B3C7D6', '#8AA7BF', '#6F8FAE'],
    particle: ['#FFFFFF', '#DFE9F2'],
    chars: ['*', '·', '✿'],
    part: 6,
    prow: 0,
    accent: '#B3C7D6',
  },
}
const TRUNK = ['#6F4E37', '#8B6A4A']
const GROUND = ['#3E5A2E', '#4F6D3A', '#5E7D44']

export function seasonOf(month: number): Season {
  if (month >= 3 && month <= 5) return 'spring'
  if (month >= 6 && month <= 8) return 'summer'
  if (month >= 9 && month <= 11) return 'autumn'
  return 'winter'
}

export function accentOf(season: Season): string {
  return SEASONS[season].accent
}

/** A small seeded generator, so one hour draws one grove. */
function rng(seed: number): (n: number) => number {
  let a = seed >>> 0
  return n => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return (((t ^ (t >>> 14)) >>> 0) % n + n) % n
  }
}

// The MOTD's two small trees (its rows 3-7), side by side, then a gap tree.
// # █ leaf, u ▄ leaf, n ▀ leaf, [ ▐ ] ▌ trunk.
const TREES = [
  '  uu##uu            uu##uu  ',
  ' ########   uu##uu ######## ',
  ' n######n  n######n n######n',
  '   n[]n      n[]n    n[]n   ',
  '    []        []      []    ',
]
const FIRST_ROW = 3

export const ART_W = TREES[0]!.length

/** The grove: five rows of trees and a ground line, for this season and hour. */
export function drawGrove(season: Season, seed: number): Line[] {
  const look = SEASONS[season]
  const r = rng(seed)
  const pick = (xs: string[]) => xs[r(xs.length)]!
  const rows: Line[] = TREES.map((tpl, i) => {
    const chance = FIRST_ROW + i < look.prow ? 0 : look.part
    const line: Line = []
    for (const ch of tpl) {
      switch (ch) {
        case '#':
          line.push({ t: '█', c: pick(look.leaf) })
          break
        case 'u':
          line.push({ t: '▄', c: pick(look.leaf) })
          break
        case 'n':
          line.push({ t: '▀', c: pick(look.leaf) })
          break
        case '[':
          line.push({ t: '▐', c: TRUNK[1] })
          break
        case ']':
          line.push({ t: '▌', c: TRUNK[1] })
          break
        default:
          line.push(r(100) < chance ? { t: pick(look.chars), c: pick(look.particle) } : { t: ' ' })
      }
    }
    return merge(line)
  })
  const ground: Line = []
  for (let i = 0; i < ART_W; i++) ground.push({ t: r(3) ? '▁' : '▂', c: pick(GROUND) })
  rows.push(merge(ground))
  return rows
}

/** Joins neighbouring runs of one style, so a line stays a few segments. */
export function merge(line: Line): Line {
  const out: Line = []
  for (const s of line) {
    const last = out[out.length - 1]
    if (last && last.c === s.c && last.b === s.b && last.i === s.i) last.t += s.t
    else out.push({ ...s })
  }
  return out
}

export const width = (line: Line): number => line.reduce((n, s) => n + [...s.t].length, 0)

/** Cuts a line to `w` cells (an ellipsis on the last), then pads it with spaces. */
export function fit(line: Line, w: number): Line {
  const out: Line = []
  let left = w
  for (const s of line) {
    if (left <= 0) break
    const cs = [...s.t]
    if (cs.length <= left) {
      out.push(s)
      left -= cs.length
    } else {
      out.push({ ...s, t: `${cs.slice(0, Math.max(0, left - 1)).join('')}…` })
      left = 0
    }
  }
  if (left > 0) out.push({ t: ' '.repeat(left) })
  return out
}

/** The MOTD's bar: 16 cells of ━, accent, amber from 75 %, red from 90 % when `isLoad`. */
export function bar(fraction: number, p: GrovePalette, accent: string, cells = 16, isLoad = false): Seg[] {
  const f = Math.max(0, Math.min(1, Number.isFinite(fraction) ? fraction : 0))
  let on = Math.round(f * cells)
  if (f > 0 && on === 0) on = 1
  const c = isLoad && f >= 0.9 ? p.red : isLoad && f >= 0.75 ? p.yellow : accent
  return [
    { t: '━'.repeat(on), c },
    { t: '━'.repeat(cells - on), c: p.track },
  ]
}

/** A row label, 7 wide (the MOTD's 6, plus room for `session`). */
export const label = (name: string, p: GrovePalette): Seg => ({ t: `${name.padEnd(7)} `, c: p.muted })

/**
 * A box with its title in the top edge and `right` at the top's end:
 * ╭─ title ──────── right ─╮ / │ row │ / ╰────────╯
 */
export function box(title: Line, right: Line, body: Line[], w: number, edge: string): Line[] {
  // ╭─ ␣title␣ ─…─ ␣right␣ ─╮ : 3 + title + 1 + fill + (1 + right) + 3 = w
  const rightW = width(right) > 0 ? width(right) + 1 : 0
  const head = cut(title, Math.max(1, w - 8 - rightW))
  const fill = Math.max(1, w - 7 - width(head) - rightW)
  const top: Line = [
    { t: '╭─ ', c: edge },
    ...head,
    { t: ` ${'─'.repeat(fill)}`, c: edge },
    ...(rightW > 0 ? [{ t: ' ' }, ...right] : []),
    { t: ' ─╮', c: edge },
  ]
  const rows = body.map(l => [{ t: '│ ', c: edge }, ...fit(l, w - 4), { t: ' │', c: edge }])
  const bottom: Line = [{ t: `╰${'─'.repeat(w - 2)}╯`, c: edge }]
  return [top, ...rows, bottom]
}

/** Like fit, without the padding. */
export function cut(line: Line, w: number): Line {
  return width(line) <= w ? line : fit(line, w)
}

const isOver = (a: GroveAgent): boolean =>
  a.status === 'done' || a.status === 'failed' || a.status === 'stopped'

/** `200k`, `1M`. */
const tokens = (n: number): string =>
  n >= 1_000_000 ? `${+(n / 1_000_000).toFixed(1)}M` : `${Math.round(n / 1000)}k`

/** Session first, then the week, then a model's own windows. */
function order(kind: string): number {
  const l = windowLabel(kind)
  return l === 'session' ? 0 : l === 'week' ? 1 : l === 'fable' ? 2 : 3
}

/** Each kind of task in one of the scheme's accents. */
function kindColor(kind: string, p: GrovePalette): string {
  switch (kind) {
    case 'research':
      return p.blue
    case 'coding':
      return p.green
    case 'testing':
      return p.yellow
    case 'review':
      return p.orange
    case 'planning':
      return p.aqua
    case 'ops':
      return p.red
    default:
      return p.muted
  }
}

export type Scene = {
  agents: GroveAgent[]
  workflows: { key: string; name: string }[]
  tasks: GroveTask[]
  palette: GrovePalette
  now: number
  tick: number
  /** Local time, for the season and the hour's grove. */
  date: { month: number; dayOfYear: number; hour: number }
  columns: number
  rows: number
  /** The main loop's model id, as /model shows it. */
  mainModel: string
  usage: GroveUsage
}

const WISDOM = [
  'The best time to plant a tree was twenty years ago. The second best time is now.',
  'Snapshots are cheap. Regret is not.',
  'A grove grows one ring at a time.',
  'Roots before branches: get DNS right first.',
  "It's always DNS. Even in the forest.",
  'Prune often, back up oftener.',
  'Measure twice, rm -rf once.',
  'Strong roots, quiet logs.',
  'Every forest was once a handful of seeds that held their ground.',
  'Leave the forest better than you found it.',
  'A tree that bends in the wind does not break. Neither does a lab with backups.',
  'Trees talk through their roots. Servers, through syslog.',
  'Plant it, label it, document it.',
  'Old trees have the deepest roots. Old configs, the deepest surprises.',
]

export const wisdomOf = (dayOfYear: number): string => WISDOM[dayOfYear % WISDOM.length]!

/** The whole pane, as lines. */
export function drawPane(s: Scene): Line[] {
  const p = s.palette
  const season = seasonOf(s.date.month)
  const ac = accentOf(season)
  const w = Math.max(40, Math.min(s.columns, 96))
  const out: Line[] = []

  // ── head: the grove on the left, the facts on the right ──
  const total = s.agents.length
  const running = s.agents.filter(a => a.status === 'running').length
  const idle = s.agents.filter(a => a.status === 'idle').length
  const finished = s.agents.filter(isOver).length
  const failed = s.agents.filter(a => a.status === 'failed' || a.status === 'stopped').length
  const firstStart = total > 0 ? Math.min(...s.agents.map(a => a.startedAt)) : s.now
  const tasksDone = s.tasks.filter(t => t.status === 'completed').length

  const info: Line[] = [
    [
      { t: ' grove', c: ac, b: true },
      { t: `  agents · ${season} · ${p.scheme}`, c: p.dim },
    ],
    [],
    [label('model', p), { t: modelName(s.mainModel || undefined), c: p.fg, b: true }, { t: '  main loop', c: p.dim }],
    total === 0
      ? [label('agents', p), { t: 'none yet: the grove is waiting', c: p.dim, i: true }]
      : [
          label('agents', p),
          ...bar(finished / total, p, ac),
          { t: ` ${finished}`, c: p.fg },
          { t: ` / ${total} done`, c: p.dim },
        ],
    total === 0
      ? [label('now', p), { t: '·', c: p.dim }]
      : [
          label('now', p),
          { t: '●', c: running > 0 ? p.green : p.dim },
          { t: ` ${running} running`, c: running > 0 ? p.fg : p.dim },
          ...(idle > 0 ? [{ t: `  ● ${idle} idle`, c: p.yellow }] : []),
          ...(failed > 0 ? [{ t: `  ✗ ${failed} failed`, c: p.red }] : []),
        ],
    s.tasks.length === 0
      ? [label('tasks', p), { t: 'no task list', c: p.dim }]
      : [
          label('tasks', p),
          ...bar(tasksDone / s.tasks.length, p, ac),
          { t: ` ${tasksDone}`, c: p.fg },
          { t: ` / ${s.tasks.length} done`, c: p.dim },
        ],
    [label('time', p), { t: total === 0 ? '·' : formatElapsed(s.now - firstStart), c: total === 0 ? p.dim : p.fg }],
  ]
  const art = drawGrove(season, s.date.dayOfYear * 7919 + s.date.hour)
  const artFits = w >= ART_W + 2 + 40
  const headRows = Math.max(info.length, artFits ? art.length : 0)
  const off = Math.floor((headRows - info.length) / 2)
  for (let i = 0; i < headRows; i++) {
    const right = info[i - off] ?? []
    out.push(artFits ? [...(art[i] ?? [{ t: ' '.repeat(ART_W) }]), { t: '  ' }, ...right] : right)
  }
  out.push([])

  // ── usage: the account's windows, the context, the cost (the status line's figures) ──
  const windows = [...s.usage.windows].sort((a, b) => order(a.kind) - order(b.kind))
  for (const win of windows) {
    const f = win.percentUsed / 100
    out.push([
      label(windowLabel(win.kind), p),
      ...bar(f, p, ac, 16, true),
      { t: ` ${Math.round(win.percentUsed)}%`, c: f >= 0.9 ? p.red : f >= 0.75 ? p.yellow : p.fg },
      { t: `  ${resetText(win.resetsAt, s.now)}`, c: p.dim },
    ])
  }
  if (!windows.some(win => windowLabel(win.kind) === 'fable')) {
    out.push([label('fable', p), { t: windows.length === 0 ? 'no reading yet' : 'no Fable window reported', c: p.dim, i: true }])
  }
  if (windows.length === 0) {
    out.push([label('limits', p), { t: 'no reading yet: they come with the next response', c: p.dim, i: true }])
  }
  if (s.usage.contextPercent !== undefined) {
    const f = s.usage.contextPercent / 100
    out.push([
      label('context', p),
      ...bar(f, p, ac, 16, true),
      { t: ` ${Math.round(s.usage.contextPercent)}%`, c: p.fg },
      { t: s.usage.contextWindow ? ` of ${tokens(s.usage.contextWindow)}` : '', c: p.dim },
    ])
  }
  if (s.usage.costUsd !== undefined) {
    out.push([label('cost', p), { t: `$${s.usage.costUsd.toFixed(2)}`, c: p.fg }, { t: '  this session', c: p.dim }])
  }
  out.push([])

  // ── the agents, one box each, a workflow's under its name ──
  const maxCalls = Math.max(1, ...s.agents.map(a => a.calls))
  const boxFor = (a: GroveAgent, bw: number): Line[] => {
    const over = isOver(a)
    const time = formatElapsed((a.endedAt ?? s.now) - a.startedAt)
    const pulse = s.tick % 2 === 0 ? p.green : p.aqua
    const [dot, edge] =
      a.status === 'running'
        ? [{ t: '●', c: pulse }, ac]
        : a.status === 'idle'
          ? [{ t: '●', c: p.yellow }, p.yellow]
          : a.status === 'done'
            ? [{ t: '✓', c: p.green }, p.track]
            : [{ t: '✗', c: p.red }, p.red]
    const title: Line = [
      dot,
      { t: ' ' },
      { t: a.type, c: over ? p.muted : ac, b: !over },
      ...(a.kind ? [{ t: ` · ${a.kind}`, c: over ? p.dim : kindColor(a.kind, p) }] : []),
    ]
    const word = a.status === 'running' ? '' : `${a.status} · `
    const right: Line = [{ t: `${word}${a.calls} call${a.calls === 1 ? '' : 's'} · `, c: p.dim }, { t: time, c: over ? p.dim : p.fg }]
    const body: Line[] = [
      [label('task', p), { t: a.description, c: over ? p.muted : p.fg }],
      [label('model', p), { t: a.model ? modelName(a.model) : 'resolving…', c: over ? p.muted : p.fg }],
    ]
    if (!over) {
      body.push([label('now', p), { t: a.now ?? 'starting…', c: p.fg }])
      body.push([label('calls', p), ...bar(a.calls / maxCalls, p, ac), { t: ` ${a.calls}`, c: p.fg }])
    } else if (a.result) {
      body.push([label('result', p), { t: a.result, c: p.dim, i: true }])
    }
    return box(title, right, body, bw, edge)
  }
  const oneLine = (a: GroveAgent, indent: number): Line => {
    const mark = a.status === 'done' ? { t: '✓', c: p.green } : { t: '✗', c: p.red }
    return fit(
      [
        { t: ' '.repeat(indent + 1) },
        mark,
        { t: ` ${a.type}`, c: p.muted },
        { t: `  ${a.description}`, c: p.dim },
        { t: `  ${formatElapsed((a.endedAt ?? s.now) - a.startedAt)}`, c: p.dim },
      ],
      w,
    )
  }

  type Item = { kind: 'agent'; a: GroveAgent } | { kind: 'group'; key: string }
  const items: Item[] = []
  const seen = new Set<string>()
  for (const a of s.agents) {
    if (!a.group) items.push({ kind: 'agent', a })
    else if (!seen.has(a.group)) {
      seen.add(a.group)
      items.push({ kind: 'group', key: a.group })
    }
  }

  // Finished agents fold to one line when the boxes would not all fit.
  const boxRows = (a: GroveAgent) => (isOver(a) ? (a.result ? 5 : 4) : 6)
  const fullHeight =
    out.length + 2 + s.agents.reduce((n, a) => n + boxRows(a), 0) + items.filter(i => i.kind === 'group').length * 2
  const fold = fullHeight > s.rows

  for (const it of items) {
    if (it.kind === 'agent') {
      if (fold && isOver(it.a)) out.push(oneLine(it.a, 0))
      else out.push(...boxFor(it.a, w))
      continue
    }
    const members = s.agents.filter(a => a.group === it.key)
    const name = s.workflows.find(g => g.key === it.key)?.name ?? 'workflow'
    const live = members.filter(a => !isOver(a)).length
    out.push([
      { t: '◆ ', c: live > 0 ? ac : p.dim },
      { t: name, c: live > 0 ? ac : p.muted, b: true },
      { t: `  ${members.length} agent${members.length === 1 ? '' : 's'} · ${live > 0 ? `${live} running` : 'done'}`, c: p.dim },
    ])
    for (const a of members) {
      if (fold && isOver(a)) out.push(oneLine(a, 2))
      else out.push(...boxFor(a, w - 2).map(l => [{ t: '  ' }, ...l]))
    }
  }

  const active = s.tasks.filter(t => t.status === 'in_progress')
  if (active.length > 0) {
    out.push([])
    for (const t of active) out.push(fit([{ t: '▸ ', c: p.yellow }, { t: t.activeForm || t.subject, c: p.fg }], w))
  }

  out.push([])
  // The wisdom wraps at word breaks, its later lines under its first word.
  const words = wisdomOf(s.date.dayOfYear).split(' ')
  const wrapped: string[] = ['']
  for (const word of words) {
    const cur = wrapped[wrapped.length - 1]!
    if (cur.length > 0 && cur.length + 1 + word.length > w - 2) wrapped.push(word)
    else wrapped[wrapped.length - 1] = cur ? `${cur} ${word}` : word
  }
  wrapped.forEach((text, i) =>
    out.push([{ t: i === 0 ? '❝ ' : '  ', c: ac }, { t: text, c: p.dim, i: true }]),
  )
  return out.map(merge)
}

/** The season's particle colors, for the desktop backdrop's falling leaves, snow or fireflies. */
export function particlesOf(season: Season): string[] {
  return [...SEASONS[season].particle]
}
