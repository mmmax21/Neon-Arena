# Neon Arena

A neon top-down arena shooter made with Godot 4 (GL Compatibility). All visuals are drawn in code and all sound effects are synthesized at runtime — no image or audio files.

**Play online:** https://mmmax21.github.io/Neon-Arena/ (pick a version)

| Version | Play | Source |
|---|---|---|
| **v2.0** (current) | https://mmmax21.github.io/Neon-Arena/v2/ | `main` branch, tag `v2.0` |
| v1.0 (original) | https://mmmax21.github.io/Neon-Arena/v1/ | `v1` branch, tag `v1.0` |

## What's new in v2.0

- **Choose a weapon:** Pulse (balanced), Scatter (shotgun), Laser (piercing beam)
- **Upgrade cards:** every 3 waves pick 1 of 3 upgrades — 14 upgrades in 4 categories (Firepower, Ballistics, Dash, Survival), e.g. pierce, ricochet, seeker shots, shockwave dash, barrier
- **Build icons:** your weapon and upgrades show as icons in the top-left; hover for details
- **7 new enemies:** splitter, dodger, laser sentry, mine layer + mines, snake (only the head takes damage)
- **Elite enemies** from wave 7 with shield / haste / volatile affixes
- **Second boss:** VOID WEAVER with rotating lasers, spiral bullets and summons (alternates with CORE WARDEN every 5 waves)
- **English / 中文** — switch on the title screen or press L any time

## Controls (v2.0)

| Action | Input |
|---|---|
| Move | WASD / Arrow keys |
| Aim | Mouse |
| Fire | Hold Left Click |
| Dash (brief invincibility) | Space / Shift / Right Click |
| Pick a card | Click, or 1 / 2 / 3 |
| Language | L |
| Pause | P / Esc |
| Retry / change weapon | R / Click (on game over) |

## v1.0

The original prototype: one blaster with a triple-shot pickup, 3 enemy types and the CORE WARDEN boss every 5 waves, English only. Check out the `v1` branch to run it.

## Run

Open the folder in Godot 4.3+ and press Play, or export with the included **Web** preset.

The Chinese font is a subset of [Noto Sans SC](https://github.com/notofonts/noto-cjk) (SIL Open Font License, see `fonts/OFL.txt`). After adding new Chinese text to `scripts/i18n.gd`, rebuild it with `tools/subset_font.py`.
