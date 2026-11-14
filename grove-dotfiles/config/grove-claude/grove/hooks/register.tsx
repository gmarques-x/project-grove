// grove: Project Grove for Claude Code.
// A live Agents pane in the look of grove-lab's MOTD (a seasonal grove, ━ bars,
// a box per agent) and a status line. Text colors follow the Everforest scheme
// grove-themes has set (re-read every 3 s, no restart).

import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { GroveAgent, GrovePalette, GroveTask, GroveUsage, GroveWorkflow } from '../types'
import {
  FALLBACK,
  capRows,
  cleanScheme,
  describeCall,
  firstLine,
  fromListStatus,
  parsePalette,
  workflowName,
  kindAfterCall,
  kindAtStart,
} from './logic'
import { drawPane } from './motd'
import type { Line } from './motd'

const PANE = 'grove-agents'
const TITLE = 'Agents'

// Change a shape tag when that value's fields change: it declines what an
// earlier version stored, which outlives a reload.
const agents = atom({ plugin: 'grove', key: 'agents' } as const, [] as GroveAgent[], { shape: 'agents-2' })
const workflows = atom({ plugin: 'grove', key: 'workflows' } as const, [] as GroveWorkflow[], {
  shape: 'workflows-1',
})
const tasks = atom({ plugin: 'grove', key: 'tasks' } as const, [] as GroveTask[], { shape: 'tasks-1' })
const palette = atom({ plugin: 'grove', key: 'palette' } as const, FALLBACK, { shape: 'palette-3' })
const tick = atom({ plugin: 'grove', key: 'tick' } as const, 0)
const paneWanted = atom({ plugin: 'grove', key: 'paneWanted' } as const, true)
const usage = atom({ plugin: 'grove', key: 'usage' } as const, { windows: [] } as GroveUsage, { shape: 'usage-1' })
const mainModel = atom({ plugin: 'grove', key: 'mainModel' } as const, '')

type UsageFigures = {
  context: { percent?: number; window: number }
  rateLimits: Array<{ kind: string; percentUsed: number; resetsAt?: string }>
  cost?: { usd: number }
}

// The status line's figures, kept for the pane's usage rows.
async function keepUsage($: EngineInterface, u: UsageFigures): Promise<void> {
  const next: GroveUsage = {
    windows: u.rateLimits.map(w => ({ kind: w.kind, percentUsed: w.percentUsed, resetsAt: w.resetsAt })),
    contextPercent: u.context.percent,
    contextWindow: u.context.window,
    costUsd: u.cost?.usd,
  }
  const was = await read($, usage)
  if (JSON.stringify(was) !== JSON.stringify(next)) await update($, usage, () => next)
}

// The main loop's model, as /model shows it.
async function keepModel($: EngineInterface, id?: string): Promise<void> {
  let model = id
  if (!model) {
    try {
      model = await $.session.model()
    } catch {
      return
    }
  }
  if (model && model !== (await read($, mainModel))) await update($, mainModel, () => model ?? '')
}

const isOver = (a: GroveAgent): boolean =>
  a.status === 'done' || a.status === 'failed' || a.status === 'stopped'

// Module variables start over on every reload; the atoms do not.
let ticker: Timer | undefined
let seq = 0

async function syncStatus($: EngineInterface): Promise<void> {
  const rows = await read($, agents)
  const status = rows.length === 0 ? undefined : summary(rows)
  $.ui.status(status)
}

function summary(rows: GroveAgent[]): string {
  const running = rows.filter(a => a.status === 'running').length
  const done = rows.filter(a => a.status === 'done').length
  const failed = rows.filter(a => a.status === 'failed' || a.status === 'stopped').length
  const parts = [running > 0 ? `${running} agent${running === 1 ? '' : 's'} running` : 'no agents running']
  if (done > 0) parts.push(`${done} done`)
  if (failed > 0) parts.push(`${failed} failed`)
  return `🌲 ${parts.join(' · ')}`
}

// One 1 s clock while any agent runs: pulses the dots, moves the times,
// and asks the engine where each agent stands.
function ensureTicker($: EngineInterface): void {
  if (ticker) return
  ticker = $.clock.every(1000, async () => {
    await update($, tick, n => n + 1)
    let listed: Awaited<ReturnType<EngineInterface['agent']['list']>> = []
    try {
      listed = await $.agent.list()
    } catch {
      listed = []
    }
    const byId = new Map(listed.map(a => [a.id, a]))
    const now = await $.clock.now()
    const rows = await update($, agents, list =>
      list.map(a => {
        if (!a.id || isOver(a)) return a
        const one = byId.get(a.id)
        const next = one ? fromListStatus(one.status) : undefined
        if (!next || next === a.status) return a
        return { ...a, status: next, endedAt: next === 'running' || next === 'idle' ? undefined : now }
      }),
    )
    await syncStatus($)
    if (!rows.some(a => a.status === 'running')) {
      ticker?.cancel()
      ticker = undefined
    }
  }) as Timer
}

async function openPane($: EngineInterface): Promise<void> {
  if (!(await read($, paneWanted))) return
  // An open of an open id only retitles it, and sets the background anew.
  void $.ui.open({ id: PANE, title: TITLE, backgroundColor: (await read($, palette)).bg })
}

// The scheme grove-themes set, and its palette file.
async function loadPalette($: EngineInterface): Promise<void> {
  const home = (await $.env.get('HOME')) ?? ''
  const state = (await $.env.get('GROVE_STATE')) ?? `${home}/.local/state/grove`
  // The mod lives at grove-dotfiles/config/grove-claude/grove: three folders up.
  const dotfiles =
    (await $.env.get('GROVE_DOTFILES')) ?? $.plugin.root.split('/').slice(0, -3).join('/')
  let next: GrovePalette = FALLBACK
  try {
    const scheme = cleanScheme(await $.fs.read(`${state}/theme`))
    if (scheme) {
      // From the checkout the mod sits in; a copy elsewhere (a session's
      // dev-mods folder) falls back to the usual checkout.
      const text = await $.fs
        .read(`${dotfiles}/theme/everforest-${scheme}`)
        .catch(() => $.fs.read(`${home}/Developer/project-grove/grove-dotfiles/theme/everforest-${scheme}`))
      next = parsePalette(text, scheme)
    }
  } catch {
    next = FALLBACK
  }
  const was = await read($, palette)
  if (JSON.stringify(was) !== JSON.stringify(next)) {
    await update($, palette, () => next)
    // A switch repaints the pane's ground too: an open of an open id sets it anew.
    if (was.bg !== next.bg && (await $.ui.panes()).some(p => p.id === PANE)) {
      void $.ui.open({ id: PANE, title: TITLE, backgroundColor: next.bg })
    }
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'grove-agents',
      description: 'Open or close the Grove Agents pane',
    })
    await loadPalette($)
    await keepModel($)
    try {
      await keepUsage($, await $.session.usage())
    } catch {
      // No figures yet: the first session.measure brings them.
    }
    $.clock.every(3000, async () => {
      await loadPalette($)
      await keepModel($)
    })
    const rows = await read($, agents)
    if (rows.some(a => a.status === 'running')) ensureTicker($)
    if (rows.length > 0) await syncStatus($)
    if (rows.length > 0 || (await $.ui.panes()).some(p => p.id === PANE)) await openPane($)
    return next(e)
  })

  on('command.run', { command: 'grove-agents' }, async $ => {
    const open = await $.ui.panes()
    if (open.some(p => p.id === PANE)) {
      await update($, paneWanted, () => false)
      await $.ui.close({ id: PANE })
      return { text: 'Agents pane closed. /grove-agents opens it again.' }
    }
    await update($, paneWanted, () => true)
    await $.ui.open({ id: PANE, title: TITLE, backgroundColor: (await read($, palette)).bg })
    return { text: 'Agents pane opened.' }
  })

  on('agent.spawn', async ($, e, next) => {
    if (e.resume) {
      const id = e.resume.agentId
      await update($, agents, list =>
        list.map(a => (a.id === id ? { ...a, status: 'running', endedAt: undefined } : a)),
      )
      ensureTicker($)
      await syncStatus($)
      return next(e)
    }

    const startedAt = await $.clock.now()
    const key = `${e.tool_use_id}:${startedAt}:${++seq}`
    const row: GroveAgent = {
      key,
      type: e.fork ? 'fork' : e.subagentType,
      description: e.description || (e.workflow ? `agent ${e.workflow.agentIndex}` : 'agent'),
      startedAt,
      status: 'running',
      calls: 0,
      group: e.workflow ? e.tool_use_id || e.workflow.runId : undefined,
      isTeammate: e.isTeammate,
      kind: kindAtStart(e.fork ? 'fork' : e.subagentType, e.description, e.prompt),
      model: e.model,
    }
    await update($, agents, list => capRows([...list, row]))
    ensureTicker($)
    await syncStatus($)
    await openPane($)

    const r = await next(e)
    if (r.deny !== undefined) {
      await update($, agents, list => list.filter(a => a.key !== key))
    } else if (r.agentId) {
      const id = r.agentId
      const model = r.model
      await update($, agents, list => list.map(a => (a.key === key ? { ...a, id, model } : a)))
    }
    await syncStatus($)
    return r
  })

  on('session.measure', async ($, e, next) => {
    await keepUsage($, e)
    return next(e)
  })

  on('classic.PostModelSwitch', async ($, e, next) => {
    await keepModel($, e.to_model)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const id = e.agentId
    if (id) {
      const endedAt = await $.clock.now()
      const result = firstLine(e.answer)
      await update($, agents, list =>
        list.map(a => {
          if (a.id !== id) return a
          if (a.isTeammate && e.reason === 'answer') return { ...a, status: 'idle', result: result || a.result }
          const status = e.reason === 'aborted' ? 'stopped' : e.reason === 'answer' ? 'done' : 'failed'
          return { ...a, status, endedAt, now: undefined, result: result || a.result }
        }),
      )
      await syncStatus($)
    }
    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    const tool = String(e.tool)
    const input = e as unknown as Record<string, unknown>

    if (e.agentId) {
      const id = e.agentId
      const now = describeCall(tool, input)
      await update($, agents, list =>
        list.map(a =>
          a.id === id
            ? {
                ...a,
                now,
                calls: a.calls + 1,
                status: a.status === 'idle' ? 'running' : a.status,
                kind: kindAfterCall(a.kind ?? 'research', tool, input),
              }
            : a,
        ),
      )
      ensureTicker($)
    } else if (tool === 'Workflow') {
      const wf: GroveWorkflow = {
        key: e.tool_use_id,
        name: workflowName(input),
        startedAt: await $.clock.now(),
      }
      await update($, workflows, list => [...list.filter(w => w.key !== wf.key), wf].slice(-10))
    }

    const ran = await next(e)
    if (ran.deny !== undefined || ran.isError) return ran

    if (tool === 'TaskCreate') {
      const res = ran.result as { task?: { id?: string; subject?: string } } | undefined
      const t = res?.task
      if (t?.id) {
        const task: GroveTask = { id: t.id, subject: t.subject ?? '', status: 'pending' }
        await update($, tasks, list => [...list.filter(x => x.id !== task.id), task])
      }
    } else if (tool === 'TaskUpdate') {
      const id = typeof input.taskId === 'string' ? input.taskId : undefined
      const status = input.status
      if (id) {
        await update($, tasks, list =>
          status === 'deleted'
            ? list.filter(x => x.id !== id)
            : list.map(x =>
                x.id !== id
                  ? x
                  : {
                      ...x,
                      subject: typeof input.subject === 'string' ? input.subject : x.subject,
                      activeForm: typeof input.activeForm === 'string' ? input.activeForm : x.activeForm,
                      status:
                        status === 'pending' || status === 'in_progress' || status === 'completed'
                          ? status
                          : x.status,
                    },
              ),
        )
      }
    }
    return ran
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text } = $.ui.resolve(e)
    const now = await $.clock.now()
    const d = new Date(now)
    const dayOfYear = Math.floor((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - Date.UTC(d.getFullYear(), 0, 0)) / 86400000)
    const lines = drawPane({
      agents: await read($, agents),
      workflows: await read($, workflows),
      tasks: await read($, tasks),
      palette: await read($, palette),
      now,
      tick: await read($, tick),
      date: { month: d.getMonth() + 1, dayOfYear, hour: d.getHours() },
      columns: e.props.bodyColumns ?? 60,
      rows: e.props.scroll?.bodyRows ?? 40,
      mainModel: await read($, mainModel),
      usage: await read($, usage),
    })
    const draw = (line: Line) => (
      <Text>
        {line.length === 0
          ? ' '
          : line.map(seg => (
              <Text color={seg.c} bold={seg.b} italic={seg.i}>
                {seg.t}
              </Text>
            ))}
      </Text>
    )
    return <Box flexDirection="column">{lines.map(draw)}</Box>
  })
}
