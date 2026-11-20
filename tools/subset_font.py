#!/usr/bin/env python3
"""Rebuild fonts/NotoSansSC-Medium.subset.otf with only the characters the game uses.

Usage (needs fonttools: pip install fonttools):
  python3 tools/subset_font.py /path/to/NotoSansSC-Medium.otf

Source font: https://github.com/notofonts/noto-cjk (Sans/SubsetOTF/SC), SIL Open Font License.
Run it again whenever scripts/i18n.gd gains Chinese characters outside GB2312.
"""
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
chars = set(chr(c) for c in range(32, 127))
for p in [root / "scripts" / "i18n.gd", root / "scripts" / "hud.gd", root / "main.gd"]:
    chars.update(p.read_text(encoding="utf-8"))
chars.update("—·→×％！？，。：；（）“”…、")
# Leaderboard names can be any common Chinese text: include all of GB2312 (6763 hanzi plus
# full-width punctuation and symbols), about 1.4 MB.
for hi in range(0xA1, 0xF8):
    for lo in range(0xA1, 0xFF):
        try:
            chars.add(bytes([hi, lo]).decode("gb2312"))
        except UnicodeDecodeError:
            pass
chars = "".join(sorted(c for c in chars if c >= " "))
out = root / "fonts" / "NotoSansSC-Medium.subset.otf"
subprocess.run(["pyftsubset", sys.argv[1], f"--text={chars}", f"--output-file={out}",
                "--layout-features=*", "--no-hinting"], check=True)
print(f"{len(chars)} characters -> {out} ({out.stat().st_size // 1024} KB)")
