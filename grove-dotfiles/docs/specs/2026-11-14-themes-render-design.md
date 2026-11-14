# Grove Themes: a render mode for screenshots

Date: 2026-11-14. Status: approved in conversation (the owner: "go ahead").

## Intent
The READMEs show Grove Explorer and Grove Keys from their `--render` sample modes, so no personal data appears. Grove Themes has no render mode, so its gallery and dropdown have no pictures. The owner wants the same for Grove Themes.

## Goals, non-goals, anti-goals
- Goals: `GroveThemes --render <gallery|dropdown> <out.png> [scheme]` draws the gallery window or the menu-bar dropdown from fixed sample data to a PNG at 2x, then exits. The Grove Themes README and the root README show the gallery in dark-medium and light-medium.
- Non-goals: rendering every state, or a test that compares pixels.
- Anti-goals: starting the app, showing a window or a menu-bar item, running `grove-themes`, writing any state, or changing the scheme.

## Approaches
- **A. Explorer's pattern. Chosen:** a `Render` enum in the GroveThemes target, run from the top of `main`/the app entry before any app code. It hosts the SwiftUI view in an off-screen `NSHostingView`, `cacheDisplay`s it into a bitmap at 2x and writes a PNG. A sample `GroveThemesClient` (or whatever protocol `ThemesModel` takes) returns a fixed list: the six schemes with the current one marked, and the logo and wallpaper choices pointing at the repo's own images, which are already public.
- B. A screenshot of the running app: rejected, because it shows the real desktop and needs Screen Recording.

## Design
- **Flags:** `--render gallery` uses `GalleryView`'s own size (760 × 763) and `--render dropdown` uses the dropdown's size. The scheme is a scheme name (default `dark-medium`) or a theme file path, as in Explorer. The colours come from that scheme, so a light render is light throughout.
- **Activation:** the activation policy is `.prohibited`, as in Explorer, and the process exits 0 after writing. A bad state name or a write error exits 1 with one line on stderr that lists the states.
- **Sample data:** the current scheme is the one being rendered. The logo and wallpaper rows use the repo's `grove-wallpapers/` and the fastfetch images, found relative to the executable's checkout through the same lookup the app uses. If they are missing, the cards keep their swatch colours.
- **READMEs:** the gallery goes into `assets/screenshots/themes-gallery-{dark,light}-medium.png`, shown in the Grove Themes README and in the root README's Screenshots section, using the `<picture>` pattern already there.

## Left to the builder
- How the sample client is shaped. Follow `ThemesModel`'s init and the existing test doubles.
- Whether the dropdown render needs a fixed width (use the app's).
