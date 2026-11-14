import { expect, test } from 'claude-code/testing'

import { capRows, describeCall, kindAfterCall, kindAtStart, modelName, parsePalette, windowLabel, workflowName } from './logic'

const PANE = {
  plugin: 'grove',
  component: 'Pane',
  requestId: 'grove-agents',
  props: {
    title: 'Agents',
    isFocused: false,
    bodyColumns: 90,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 30 },
    view: {},
  },
} as const

const LIGHT = `# Everforest Light Medium
bg0    = #FDF6E3
fg     = #5C6A72
green  = #8DA101
yellow = #DFA000
red    = #F85552
aqua   = #35A77C
blue   = #3A94C5
orange = #F57D26
dim    = #939F91
muted  = #829181
`

// Stands for the engine beneath the mod in every test.
const status: Array<string | undefined> = []
const opened: Array<{ backgroundColor?: string }> = []
const reads: string[] = []
let env: Record<string, string> = {}

function engine(on: any, files: Record<string, string>, listed: () => unknown[] = () => []) {
  on('ui.status', (_: unknown, e: { text?: string }) => {
    status.push(e.text)
    return { value: undefined }
  })
  let t = 1_000_000
  on('clock.now', () => ({ value: (t += 1000) }))
  on('clock.every', () => ({ deny: 'no timers in tests' }))
  on('command.register', () => ({ value: { command: 'grove-agents' } }))
  on('ui.open', (_: unknown, e: { backgroundColor?: string }) => {
    opened.push(e)
    return { value: { isPlaced: true } }
  })
  on('ui.panes', () => ({ value: [] }))
  on('env.get', (_: unknown, e: { name: string }) => ({
    value: e.name === 'HOME' ? '/home/t' : env[e.name],
  }))
  on('fs.read', (_: unknown, e: { path: string }) => {
    reads.push(e.path)
    // A key starting with * matches the end of the path read.
    const hit = Object.keys(files).find(k => (k.startsWith('*') ? e.path.endsWith(k.slice(1)) : k === e.path))
    const text = hit === undefined ? undefined : files[hit]
    if (text === undefined) throw new Error('ENOENT')
    return { value: text }
  })
  on('agent.list', () => ({ value: listed() }))
  on('session.start', (_: unknown, e: { cwd: string }) => ({ cwd: e.cwd }))
  on('agent.spawn', () => ({ model: 'claude-haiku-5-5', agentId: 'ag1' }))
  on('tool.call', () => ({ result: {} }))
  on('turn.complete', (_: unknown, e: { answer: string }) => ({ text: e.answer }))
}

test('helpers', () => {
  expect(describeCall('Read', { file_path: '/a/b/theme.ts' })).toBe('reading theme.ts')
  expect(describeCall('Bash', { command: 'git log --oneline' })).toBe('running: git log --oneline')
  expect(describeCall('Grep', { pattern: 'foo' })).toBe("searching 'foo'")
  expect(workflowName({ script: "export const meta = { name: 'review-changes' }" })).toBe('review-changes')
  const p = parsePalette(LIGHT, 'light-medium')
  expect(p.green).toBe('#8DA101')
  expect(p.fg).toBe('#5C6A72')
  const rows = Array.from({ length: 32 }, (_, i) => ({ status: i < 5 ? ('done' as const) : ('running' as const), i }))
  const capped = capRows(rows)
  expect(capped.length).toBe(30)
  expect(capped[0]?.i).toBe(2)
})

test('an agent shows, says what it does, then finishes', async ($, on) => {
  engine(on, {})
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  const ui0 = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui0.find({ type: 'Text', text: /the grove is waiting/ }))?.text).toContain('none yet')
  await ui0.unmount()

  await $.agent.spawn({ prompt: 'Find the theme state files.', description: 'find theme state', subagentType: 'Explore' } as any)
  await $.tool.call({ tool: 'Read', file_path: '/x/theme.ts', agentId: 'ag1' } as any)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /Explore/ }))?.text).toContain('Explore')
    expect((await ui.find({ type: 'Text', text: /reading theme\.ts/ }))?.text).toContain('reading theme.ts')
    expect((await ui.find({ type: 'Text', text: /╭─ ● Explore/ }))?.text).toMatch(/1 call · 0:\d\d ─╮$/)
    await ui.unmount()
  }

  await $.turn.complete({ answer: 'Found it in ~/.local/state/grove/theme', agentId: 'ag1', reason: 'answer' } as any)
  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /Found it/ }))?.text).toContain('Found it in')
  expect((await ui.find({ type: 'Text', text: /╭─ ✓ Explore/ }))?.text).toMatch(/done · 1 call · 0:\d\d ─╮$/)
  expect(status.at(-1)).toBe('🌲 no agents running · 1 done')
  await ui.unmount()
})

test('colors follow the scheme grove-themes set', async ($, on) => {
  engine(on, {
    '/home/t/.local/state/grove/theme': 'light-medium\n',
    '*/grove-dotfiles/theme/everforest-light-medium': LIGHT,
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.agent.spawn({ prompt: 'p', description: 'look around', subagentType: 'Explore' } as any)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const desc = await ui.find({ type: 'Text', text: /look around/ })
  expect(JSON.stringify(desc)).toContain('#5C6A72')
  await ui.unmount()
})

test('a missing state file falls back to Dark Medium', async ($, on) => {
  engine(on, {})
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.agent.spawn({ prompt: 'p', description: 'look around', subagentType: 'Explore' } as any)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  const desc = await ui.find({ type: 'Text', text: /look around/ })
  expect(JSON.stringify(desc)).toContain('#D3C6AA')
  await ui.unmount()
})

test("a workflow's agents sit under its name", async ($, on) => {
  engine(on, {})
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.tool.call({
    tool: 'Workflow',
    tool_use_id: 'wf-call',
    script: "export const meta = { name: 'review-changes', description: 'x' }",
  } as any)
  await $.agent.spawn({
    prompt: 'p', description: 'review bugs', subagentType: 'general-purpose',
    tool_use_id: 'wf-call', workflow: { runId: 'wf_abc123', agentIndex: 1 },
  } as any)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /◆ review-changes/ }))?.text).toMatch(/◆ review-changes\s+1 agent · 1 running/)
  expect((await ui.find({ type: 'Text', text: /general-purpose/ }))?.text).toMatch(/^\s{2}╭─ ● general-purpose/)
  await ui.unmount()
})

import { drawPane, width } from './motd'
import { FALLBACK } from './logic'

test('every box line is exactly the pane width', () => {
  const t0 = 1_000_000
  const lines = drawPane({
    agents: [
      { key: 'a', id: 'a', type: 'Explore', description: 'Survey grove-themes structure', startedAt: t0, status: 'running', now: 'reading steps.sh', calls: 4 },
      { key: 'b', id: 'b', type: 'Explore', description: 'List grove-dotfiles modules', startedAt: t0, endedAt: t0 + 23_000, status: 'done', calls: 3, result: 'There are 17 module folders' },
    ],
    workflows: [], tasks: [], palette: FALLBACK, now: t0 + 42_000, tick: 0,
    date: { month: 11, dayOfYear: 318, hour: 14 }, columns: 70, rows: 60,
    mainModel: 'claude-opus-5-5', usage: { windows: [] },
  })
  for (const l of lines) {
    const text = l.map(s => s.t).join('')
    if (/^[╭│╰]/.test(text)) expect(width(l)).toBe(70)
  }
})

test('preview', () => {
  const t0 = 1_000_000
  const esc = (hex?: string) => (hex ? `\x1b[38;2;${parseInt(hex.slice(1, 3), 16)};${parseInt(hex.slice(3, 5), 16)};${parseInt(hex.slice(5, 7), 16)}m` : '')
  const lines = drawPane({
    agents: [
      { key: 'a', id: 'a', type: 'Explore', description: 'Survey grove-themes structure', startedAt: t0, status: 'running', now: 'reading lib/steps.sh', calls: 5, model: 'claude-haiku-5-5', kind: 'research' },
      { key: 'b', id: 'b', type: 'general-purpose', description: 'Write the 93-claude-mod module', startedAt: t0, endedAt: t0 + 23_000, status: 'done', calls: 3, result: 'The module and its 13 tests are in place.', model: 'claude-sonnet-5-5', kind: 'coding' },
      { key: 'c', id: 'c', type: 'general-purpose', description: 'review bugs', startedAt: t0 + 5000, status: 'running', now: 'running: bats tests/modules_claude_mod.bats', calls: 9, group: 'wf', model: 'claude-opus-5-5', kind: 'testing' },
      { key: 'd', id: 'd', type: 'general-purpose', description: 'review perf', startedAt: t0 + 5000, endedAt: t0 + 30_000, status: 'failed', calls: 2, group: 'wf', model: 'claude-opus-5-5', kind: 'review' },
    ],
    workflows: [{ key: 'wf', name: 'review-changes' }],
    tasks: [
      { id: '1', subject: 'Build pane', status: 'completed' },
      { id: '2', subject: 'Theme it', status: 'in_progress', activeForm: 'Theming the pane like the MOTD' },
      { id: '3', subject: 'Ship', status: 'pending' },
    ],
    palette: FALLBACK, now: t0 + 42_000, tick: 0,
    date: { month: 11, dayOfYear: 318, hour: 14 }, columns: 72, rows: 80,
    mainModel: 'claude-opus-5-5[1m]',
    usage: {
      windows: [
        { kind: 'seven_day', percentUsed: 41, resetsAt: '2026-11-19T09:00:00Z' },
        { kind: 'five_hour', percentUsed: 23.5, resetsAt: new Date(t0 + 3 * 3600_000).toISOString() },
        { kind: 'seven_day_fable', percentUsed: 78 },
      ],
      contextPercent: 34, contextWindow: 1_000_000, costUsd: 4.27,
    },
  })
  const ansi = lines.map(l => l.map(s => `${s.b ? '\x1b[1m' : ''}${s.i ? '\x1b[3m' : ''}${esc(s.c)}${s.t}\x1b[0m`).join('')).join('\n')
  ;(globalThis as { console?: { log: (s: string) => void } }).console?.log(`PREVIEW-START\n${ansi}\nPREVIEW-END`)
})

test("the pane's background is the terminal's (bg0 of the current scheme)", async ($, on) => {
  engine(on, {
    '/home/t/.local/state/grove/theme': 'light-medium\n',
    '*/grove-dotfiles/theme/everforest-light-medium': LIGHT,
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.agent.spawn({ prompt: 'p', description: 'look around', subagentType: 'Explore' } as any)
  expect(opened.at(-1)?.backgroundColor).toBe('#FDF6E3')
})

test('the palette is found from where the mod sits in grove-dotfiles', async ($, on) => {
  env = {}
  reads.length = 0
  engine(on, {
    '/home/t/.local/state/grove/theme': 'light-medium\n',
    '*/grove-dotfiles/theme/everforest-light-medium': LIGHT,
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  const palette = reads.find(r => r.includes('everforest-'))
  // Three folders up from config/grove-claude/grove is the grove-dotfiles root.
  expect(palette).toMatch(/\/grove-dotfiles\/theme\/everforest-light-medium$/)
  expect(palette).not.toContain('/config/')
  expect(palette).not.toContain('/home/t/Developer')
})

test('GROVE_DOTFILES and GROVE_STATE override where it looks', async ($, on) => {
  env = { GROVE_DOTFILES: '/elsewhere/dotfiles', GROVE_STATE: '/elsewhere/state' }
  reads.length = 0
  engine(on, {
    '/elsewhere/state/theme': 'light-medium\n',
    '/elsewhere/dotfiles/theme/everforest-light-medium': LIGHT,
  })
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  expect(reads).toContain('/elsewhere/dotfiles/theme/everforest-light-medium')
  env = {}
})

test('model names, task kinds and window labels', () => {
  expect(modelName('claude-opus-5-5[1m]')).toBe('Opus 5.5 (1M)')
  expect(modelName('claude-haiku-5-5')).toBe('Haiku 5.5')
  expect(modelName('claude-sonnet-4-5-20250929')).toBe('Sonnet 4.5')
  expect(modelName('us.anthropic.claude-fable-5-2-v1:0')).toBe('Fable 5.2')
  expect(modelName('haiku')).toBe('Haiku')
  expect(kindAtStart('Explore', 'Implement it', '')).toBe('research')
  expect(kindAtStart('general-purpose', 'Write the bats tests', '')).toBe('testing')
  expect(kindAtStart('general-purpose', 'Fix the tray click', '')).toBe('coding')
  expect(kindAtStart('general-purpose', 'Review the diff', '')).toBe('review')
  expect(kindAtStart('Plan', 'anything', '')).toBe('planning')
  expect(kindAtStart('general-purpose', 'Survey the modules', '')).toBe('research')
  expect(kindAfterCall('research', 'Edit', { file_path: '/a/b.ts' })).toBe('coding')
  expect(kindAfterCall('coding', 'Write', { file_path: '/a/tests/x.bats' })).toBe('testing')
  expect(kindAfterCall('coding', 'Bash', { command: 'bats tests/x.bats' })).toBe('testing')
  expect(kindAfterCall('review', 'Edit', { file_path: '/a/b.ts' })).toBe('review')
  expect(windowLabel('five_hour')).toBe('session')
  expect(windowLabel('seven_day')).toBe('week')
  expect(windowLabel('seven_day_fable')).toBe('fable')
})

test('an agent box shows its model and kind; the head shows the main model and usage', async ($, on) => {
  engine(on, {})
  on('session.model', () => ({ value: 'claude-opus-5-5' }))
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      context: { window: 200000, percent: 12 },
      rateLimits: [{ kind: 'five_hour', percentUsed: 23.5 }, { kind: 'seven_day', percentUsed: 41 }],
      cost: { usd: 1.5 },
    },
  }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await $.agent.spawn({ prompt: 'Run the bats suite and report.', description: 'run the tests', subagentType: 'general-purpose' } as any)

  const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect((await ui.find({ type: 'Text', text: /╭─ ● general-purpose · testing/ }))?.text).toBeTruthy()
  expect((await ui.find({ type: 'Text', text: /model\s+Haiku 5\.5/ }))?.text).toBeTruthy()
  expect((await ui.find({ type: 'Text', text: /model\s+Opus 5\.5\s+main loop/ }))?.text).toBeTruthy()
  expect((await ui.find({ type: 'Text', text: /session .* 24%/ }))?.text).toBeTruthy()
  expect((await ui.find({ type: 'Text', text: /week .* 41%/ }))?.text).toBeTruthy()
  expect((await ui.find({ type: 'Text', text: /fable\s+no Fable window reported/ }))?.text).toBeTruthy()
  expect((await ui.find({ type: 'Text', text: /cost\s+\$1\.50/ }))?.text).toBeTruthy()
  await ui.unmount()
})
