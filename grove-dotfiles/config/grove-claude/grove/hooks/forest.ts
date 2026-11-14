// The desktop and mobile apps' backdrop: a pine forest at the window's edges,
// drifting mist and the season's particles (petals, fireflies, leaves, snow).
// One SVG serves both modes: its colors switch on prefers-color-scheme. The
// pines keep to the sides, away from the middle (the words) and the foot (the
// message box). Animated with CSS only: no script, nothing loaded.
// Pure: no `$`.

import type { Named } from './look'
import type { Season } from './motd'
import { particlesOf } from './motd'

const W = 1600
const H = 1000

/** A small seeded generator, so one scheme and season always draw one forest. */
function rng(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) >>> 0
    let t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

const n = (v: number): string => String(Math.round(v * 10) / 10)

/** One pine: four tiers narrowing to the tip, and a short trunk. */
function pine(x: number, base: number, h: number, w: number): string {
  const tiers = 4
  let d = `M${n(x - w * 0.06)} ${n(base)}h${n(w * 0.12)}v${n(-h * 0.12)}h${n(-w * 0.12)}Z`
  for (let i = 0; i < tiers; i++) {
    const top = base - h * (0.32 + (i * 0.68) / tiers) - h * 0.2
    const bottom = base - h * 0.1 - (i * h * 0.62) / tiers
    const half = (w / 2) * (1 - i / (tiers + 0.6))
    d += `M${n(x)} ${n(top)}L${n(x + half)} ${n(bottom)}L${n(x - half)} ${n(bottom)}Z`
  }
  return d
}

// Each edge's stand of pines is EDGE_W wide. The root's slice crops the sides
// of a box narrower than 16:10, so media rules on the scene's own aspect slide
// each stand inward by what the crop takes: a tall phone or a narrow window
// crops the sky, never the trees.
const EDGE_W = 520

/** For a box of aspect `a` (< W/H), how much the slice crops from each side, in user units. */
const cropAt = (a: number): number => Math.max(0, W / 2 - (H * a) / 2)

// Aspect bands, widest first: each band slides by the crop at its narrow end.
const BANDS: Array<[string, number]> = [
  ['1.6/1', 1.6],
  ['1.3/1', 1.3],
  ['1/1', 1.0],
  ['3/4', 0.75],
  ['9/16', 0.5625],
  ['1/3', 0.34],
]

// A stand takes at most this share of the visible width, so on a phone the
// middle stays clear: narrow boxes shrink the stands from their bottom corner.
const STAND_SHARE = 0.42

function slideRules(): string {
  let css = '.l{transform-origin:0px 1000px}.r{transform-origin:1600px 1000px}'
  for (let i = 1; i < BANDS.length; i++) {
    const [ratio] = BANDS[i - 1]!
    const [, narrow] = BANDS[i]!
    const dx = Math.round(cropAt(narrow))
    const k = Math.min(1, Math.round(((STAND_SHARE * H * narrow) / EDGE_W) * 100) / 100)
    css += `@media (max-aspect-ratio: ${ratio}){.l{transform:translateX(${dx}px) scale(${k})}.r{transform:translateX(-${dx}px) scale(${k})}}`
  }
  return css
}

/** A band of pines in an edge box, densest at its outer side; `depth` 0 far … 2 near. */
function band(r: () => number, depth: number): string {
  const count = [8, 6, 4][depth] ?? 5
  const reach = [500, 400, 300][depth] ?? 400
  const size = [330, 520, 760][depth] ?? 520
  let d = ''
  for (let i = 0; i < count; i++) {
    const t = (i + r() * 0.8) / count
    const x = t * t * reach - 30
    const h = size * (0.8 + r() * 0.4) * (1 - t * 0.35)
    d += pine(x, H + 10 - depth * 6, h, h * 0.42)
  }
  return d
}

/** One edge's stand: three depths of pines, the near one swaying. */
function stand(r: () => number, side: 0 | 1): string {
  const flip = side === 1 ? ` transform="translate(${W} 0) scale(-1 1)"` : ''
  return (
    `<g class="${side === 0 ? 'l' : 'r'}"><g${flip}>` +
    `<path class="far" d="${band(r, 0)}"/><path class="mid" d="${band(r, 1)}"/>` +
    `<g class="sway"><path class="near" d="${band(r, 2)}"/></g></g></g>`
  )
}

function particles(r: () => number, season: Season): string {
  const colors = particlesOf(season)
  const out: string[] = []
  const count = season === 'summer' ? 26 : 38
  for (let i = 0; i < count; i++) {
    // Mostly in the outer thirds, a few across the top.
    const side = r()
    const x = side < 0.42 ? r() * W * 0.3 : side < 0.84 ? W - r() * W * 0.3 : W * 0.3 + r() * W * 0.4
    const y = season === 'summer' ? H * 0.45 + r() * H * 0.5 : -40 - r() * 200
    const size = season === 'winter' ? 2 + r() * 2.5 : 2.5 + r() * 3
    const dur = season === 'summer' ? 3 + r() * 4 : 14 + r() * 16
    const delay = -r() * dur
    const color = colors[Math.floor(r() * colors.length)] ?? '#D3C6AA'
    const kind = season === 'summer' ? 'glow' : season === 'winter' ? 'snow' : 'leaf'
    const shape =
      kind === 'leaf'
        ? `<ellipse rx="${n(size * 1.6)}" ry="${n(size * 0.8)}" fill="${color}"/>`
        : `<circle r="${n(size)}" fill="${color}"/>`
    out.push(
      `<g transform="translate(${n(x)} ${n(y)})"><g class="${kind}" style="animation-duration:${n(dur)}s;animation-delay:${n(delay)}s">${shape}</g></g>`,
    )
  }
  return out.join('')
}

/**
 * The scene's SVG. `dark` and `light` are the two schemes' palettes; the seed
 * keeps one scheme and season drawing the same forest.
 */
export function forestSvg(dark: Named, light: Named, season: Season, seed = 7919): string {
  const r = rng(seed)
  const c = (p: Named, name: string, fb: string) => p[name] ?? fb
  const style = `
:root{--sky0:${c(light, 'bg0', '#FDF6E3')};--sky1:${c(light, 'bg2', '#EFEBD4')};--far:${c(light, 'bg3', '#E6E2CC')};--mid:${c(light, 'bg4', '#E0DCC7')};--near:${c(light, 'bg5', '#BDC3AF')};--mist:${c(light, 'bg0', '#FDF6E3')}}
@media (prefers-color-scheme: dark){:root{--sky0:${c(dark, 'bg_dim', '#232A2E')};--sky1:${c(dark, 'bg0', '#2D353B')};--far:${c(dark, 'bg2', '#3D484D')};--mid:${c(dark, 'bg1', '#343F44')};--near:${c(dark, 'bg_dim', '#232A2E')};--mist:${c(dark, 'grey0', '#7A8478')}}}
.s0{stop-color:var(--sky0)}.s1{stop-color:var(--sky1)}
.far{fill:var(--far)}.mid{fill:var(--mid)}.near{fill:var(--near)}
.mist{fill:var(--mist);opacity:.16;animation:drift 70s ease-in-out infinite alternate}
.mist.b{opacity:.1;animation-duration:95s;animation-direction:alternate-reverse}
.sway{transform-box:fill-box;transform-origin:50% 100%;animation:sway 11s ease-in-out infinite alternate}
.leaf{animation:fall 20s linear infinite}
.snow{animation:snow 20s linear infinite}
.glow{animation:glow 4s ease-in-out infinite alternate;opacity:0}
@keyframes drift{from{transform:translateX(-90px)}to{transform:translateX(90px)}}
@keyframes sway{from{transform:rotate(-.5deg)}to{transform:rotate(.5deg)}}
@keyframes fall{0%{transform:translate(0,0) rotate(0)}50%{transform:translate(60px,${H * 0.6}px) rotate(200deg)}100%{transform:translate(-20px,${H + 260}px) rotate(400deg)}}
@keyframes snow{0%{transform:translate(0,0)}50%{transform:translate(30px,${H * 0.6}px)}100%{transform:translate(-10px,${H + 260}px)}}
@keyframes glow{from{opacity:0;transform:translate(0,0)}to{opacity:.9;transform:translate(14px,-22px)}}
${slideRules()}
@media (prefers-reduced-motion: reduce){*{animation:none!important}.glow{opacity:.6}}`
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMid slice">`,
    `<style>${style}</style>`,
    `<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" class="s0"/><stop offset="1" class="s1"/></linearGradient>`,
    `<filter id="soft" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="40"/></filter></defs>`,
    `<rect width="${W}" height="${H}" fill="url(#sky)"/>`,
    `<g filter="url(#soft)"><ellipse class="mist" cx="${W * 0.5}" cy="${H * 0.72}" rx="${W * 0.55}" ry="90"/><ellipse class="mist b" cx="${W * 0.35}" cy="${H * 0.55}" rx="${W * 0.4}" ry="70"/></g>`,
    stand(r, 0),
    stand(r, 1),
    `<g>${particles(r, season)}</g>`,
    `</svg>`,
  ].join('')
}
