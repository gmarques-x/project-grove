// The desktop and mobile apps' look, from the Everforest scheme grove-themes
// set and its partner of the other mode at the same contrast (dark-medium ↔
// light-medium). The terminal draws no look; the Agents pane covers it.
// Pure: no `$`. Built with the skill's makeColors (copied as it is).

import type { ThemeColors } from 'claude-code'

import { makeColors } from './make-colors.js'

export type Named = Record<string, string>

const pick = (p: Named, name: string, fallback: string): string => p[name] ?? fallback

/** `a` moved toward `b` by `t` (0 → a, 1 → b), in sRGB: for text a step stronger than a grey. */
export function mix(a: string, b: string, t: number): string {
  const ch = (h: string, i: number) => parseInt(h.slice(1 + i * 2, 3 + i * 2), 16)
  const out = [0, 1, 2].map(i => Math.round(ch(a, i) + (ch(b, i) - ch(a, i)) * t))
  return `#${out.map(v => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`
}

// How far the light mode's secondary and muted text sit from fg toward grey2.
// Everforest's light greys are softer than Desktop's floor, so they lean to fg.
export const LIGHT_SECONDARY = 0.35
export const LIGHT_MUTED = 0.6

/**
 * The look for both modes. `dark` and `light` are the two schemes' palettes
 * (readNamed of theme/everforest-<scheme>).
 *
 * Dark: the page is bg0 (Ghostty's background); cards, panels and menus are
 * bg1, one step up (bg2 for menus left a highlight too faint in dark-hard).
 * Light: the page is bg1 and cards, panels and menus the lighter bg0, as light
 * mode wants its page darkest; its secondary and muted text lean from grey2
 * toward fg, as Everforest's light greys sit under Desktop's contrast floor.
 */
export function lookFor(dark: Named, light: Named, label: string): { theme: ThemeColors; problems: string[] } {
  const roles = (p: Named) => ({
    accent: pick(p, 'green', '#A7C080'),
    danger: pick(p, 'red', '#E67E80'),
    success: pick(p, 'aqua', '#83C092'),
    warning: pick(p, 'yellow', '#DBBC7F'),
    pro: pick(p, 'purple', '#D699B6'),
  })
  const git = (p: Named) => ({
    added: pick(p, 'green', '#A7C080'),
    removed: pick(p, 'red', '#E67E80'),
    modified: pick(p, 'blue', '#7FBBB3'),
    merged: pick(p, 'purple', '#D699B6'),
    conflicting: pick(p, 'orange', '#E69875'),
  })
  return makeColors({
    label,
    id: 'grove-everforest',
    dark: {
      gray: {
        anchors: {
          'surface-0': pick(dark, 'bg0', '#2D353B'),
          'surface-1': pick(dark, 'bg1', '#343F44'),
          'surface-2': pick(dark, 'bg1', '#343F44'),
          'surface-3': pick(dark, 'bg1', '#343F44'),
          'text-primary': pick(dark, 'fg', '#D3C6AA'),
          'text-secondary': pick(dark, 'grey2', '#9DA9A0'),
          'text-muted': pick(dark, 'grey2', '#9DA9A0'),
        },
      },
      // Everforest's yellow fills light in dark mode; comment highlights (45 % of
      // the warning fill) need a deeper stop of it under fg.
      // Success text in dark mode is its stop 400: pinned to aqua itself, as the
      // generated stop came out too deep on dark-soft's lighter surfaces.
      roles: {
        ...roles(dark),
        warning: { seed: pick(dark, 'yellow', '#DBBC7F'), fillShade: 300 },
        success: { seed: pick(dark, 'aqua', '#83C092'), stops: { 400: pick(dark, 'aqua', '#83C092') } },
      },
      git: git(dark),
    },
    light: {
      gray: {
        anchors: {
          'surface-0': pick(light, 'bg1', '#F4F0D9'),
          'surface-1': pick(light, 'bg0', '#FDF6E3'),
          'surface-2': pick(light, 'bg0', '#FDF6E3'),
          'surface-3': pick(light, 'bg0', '#FDF6E3'),
          'text-primary': pick(light, 'fg', '#5C6A72'),
          'text-secondary': mix(pick(light, 'fg', '#5C6A72'), pick(light, 'grey2', '#829181'), LIGHT_SECONDARY),
          'text-muted': mix(pick(light, 'fg', '#5C6A72'), pick(light, 'grey2', '#829181'), LIGHT_MUTED),
        },
      },
      roles: roles(light),
      git: git(light),
    },
  })
}

/** The lines that would stop Desktop painting the look at all. */
export const unpainted = (problems: string[]): string[] =>
  problems.filter(line => line.startsWith("Desktop won't paint"))
