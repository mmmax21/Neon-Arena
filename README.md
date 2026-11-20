# Neon Arena

A neon top-down arena shooter made with Godot 4 (GL Compatibility). All visuals are drawn in code and all sound effects are synthesized at runtime — no image or audio files.

**Play online:** https://mmmax21.github.io/Neon-Arena/ (pick a version)

| Version | Play | Source |
|---|---|---|
| **v2.2** (current) | https://mmmax21.github.io/Neon-Arena/v2/ | `main` branch, tag `v2.2` (earlier: tags `v2.1`, `v2.0`) |
| v1.0 (original) | https://mmmax21.github.io/Neon-Arena/v1/ | `v1` branch, tag `v1.0` |

## What's new in v2.2 (Season 1)

- **Online leaderboards:** separate boards for PC / phone / tablet and each control mode, with all-time, weekly and daily views. Tap your name to rename. Season 1 starts here.
- **Online co-op (2 players):** create a room, send the 4-letter code to a friend, pick weapons and go. Each pilot has their own build; a downed pilot returns when the wave is cleared.
- **Bigger arena with a follow camera:** the arena is 1.4× larger; the camera leads toward your aim, and arrows on the screen edge point at enemies and spawn warnings off-screen
- **Less crowding:** at most 22 enemies on the field (18 on touch screens) — the rest queue up — and enemies push apart instead of stacking
- **Boss phases, evolution cards, wave pacing, smoother screen shake** with a reduce-shake setting
- Server code (Cloudflare Workers + D1 + Durable Objects) is in `server/`

## What's new in v2.1

- **Play on phones and tablets** (landscape): drag on the left half to move; weapons auto-aim and auto-fire; drag on the right half to aim yourself (hybrid mode). Dash button, target lock, pause button. Three control modes: Hybrid / Auto / Twin-stick
- **Arena shifts:** after every upgrade pick the arena changes to one of 6 layouts — crystal cover you can shoot apart, alternating laser fences, conveyor belts, twin portals
- **Mute button** in the top-right corner (or press M)

## What's new in v2.0

- **Choose a weapon:** Pulse (balanced), Scatter (shotgun), Laser (piercing beam)
- **Upgrade cards:** every 3 waves pick 1 of 3 upgrades — 14 upgrades in 4 categories (Firepower, Ballistics, Dash, Survival), e.g. pierce, ricochet, seeker shots, shockwave dash, barrier
- **Build icons:** your weapon and upgrades show as icons in the top-left; hover for details
- **7 new enemies:** splitter, dodger, laser sentry, mine layer + mines, snake (only the head takes damage)
- **Elite enemies** from wave 7 with shield / haste / volatile affixes
- **Second boss:** VOID WEAVER with rotating lasers, spiral bullets and summons (alternates with CORE WARDEN every 5 waves)
- **English / 中文** — switch on the title screen or press L any time

## Controls (desktop)

| Action | Input |
|---|---|
| Move | WASD / Arrow keys |
| Aim | Mouse |
| Fire | Hold Left Click |
| Dash (brief invincibility) | Space / Shift / Right Click |
| Pick a card | Click, or 1 / 2 / 3 |
| Language | L |
| Mute | M / speaker button |
| Pause | P / Esc |
| Retry / change weapon | R / Click (on game over) |

## Controls (touch)

| Action | Input |
|---|---|
| Move | Drag anywhere on the left half |
| Aim / fire | Automatic; in Hybrid mode drag on the right half to aim and fire manually |
| Dash | Big bottom-right button |
| Lock target | Small button next to it |
| Pause | Button under the speaker, top-right |
| Control mode | "Controls" button on the title or pause screen |

## v1.0

The original prototype: one blaster with a triple-shot pickup, 3 enemy types and the CORE WARDEN boss every 5 waves, English only. Check out the `v1` branch to run it.

## Run

Open the folder in Godot 4.3+ and press Play, or export with the included **Web** preset.

The Chinese font is a subset of [Noto Sans SC](https://github.com/notofonts/noto-cjk) (SIL Open Font License, see `fonts/OFL.txt`). After adding new Chinese text to `scripts/i18n.gd`, rebuild it with `tools/subset_font.py`.
