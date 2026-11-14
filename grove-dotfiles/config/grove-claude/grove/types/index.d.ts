// The grove mod's state contract.

export type GroveAgentStatus = 'running' | 'idle' | 'done' | 'failed' | 'stopped'

export type GroveAgent = {
  /** Row key: the spawn's tool_use_id plus a counter, fixed for the row's life. */
  key: string
  /** The agent's id once the spawn has answered it (tool.call `agentId`). */
  id?: string
  type: string
  description: string
  startedAt: number
  endedAt?: number
  status: GroveAgentStatus
  /** What it is doing now, from its latest tool call ("reading x.ts"). */
  now?: string
  calls: number
  /** First line of its final answer. */
  result?: string
  /** The workflow group key (the Workflow call's tool_use_id), if any. */
  group?: string
  isTeammate?: boolean
  /** The model it runs on, as the spawn resolved it (`claude-haiku-5-5`). */
  model?: string
  /** What kind of task it is on, guessed at the start and refined by its tool calls. */
  kind?: 'research' | 'coding' | 'testing' | 'review' | 'planning' | 'ops' | 'writing'
}

export type GroveWorkflow = { key: string; name: string; startedAt: number }

export type GroveTask = {
  id: string
  subject: string
  status: 'pending' | 'in_progress' | 'completed'
  activeForm?: string
}

/** Color roles the pane paints with, as six-digit hex. */
export type GrovePalette = {
  scheme: string
  green: string
  yellow: string
  red: string
  aqua: string
  blue: string
  orange: string
  fg: string
  dim: string
  muted: string
  /** The empty part of a bar, and a finished box's edge. */
  track: string
  /** The terminal's background (bg0, what Ghostty's `background` is rendered from). */
  bg: string
}

/** The account's usage as the status line has it (`$.session.usage()`). */
export type GroveUsage = {
  windows: Array<{ kind: string; percentUsed: number; resetsAt?: string }>
  contextPercent?: number
  contextWindow?: number
  costUsd?: number
}

/** The two palettes the desktop look is built from: the scheme and its partner. */
export type GroveLook = {
  scheme: string
  dark: Record<string, string>
  light: Record<string, string>
}

declare module 'claude-code' {
  interface PluginState {
    grove: {
      agents: Shaped<GroveAgent[]>
      workflows: Shaped<GroveWorkflow[]>
      tasks: Shaped<GroveTask[]>
      palette: Shaped<GrovePalette>
      tick: number
      paneWanted: boolean
      usage: Shaped<GroveUsage>
      mainModel: string
      look: Shaped<GroveLook>
    }
  }
}
