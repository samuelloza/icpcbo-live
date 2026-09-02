#!/usr/bin/env python3

from html import escape
from pathlib import Path
import sys


def pick_font_size(name: str) -> int:
    if len(name) > 28:
        return 64
    if len(name) > 18:
        return 80
    return 100


def main() -> None:
    name = sys.argv[1].strip() or "Equipo"
    team_id = sys.argv[2].strip()
    output = Path(sys.argv[3])
    output.parent.mkdir(parents=True, exist_ok=True)

    subtitle = f"Equipo: {team_id}" if team_id else "ICPC Bolivia"
    font_size = pick_font_size(name)

    svg = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <rect width="1920" height="1080" fill="#000000"/>
  <text x="960" y="460" fill="#f4f0dd" font-family="Share, Fira Sans, sans-serif"
        font-size="36" text-anchor="middle" letter-spacing="8">ICPC BOLIVIA</text>
  <text x="960" y="590" fill="#ffffff" font-family="Fira Sans, sans-serif"
        font-size="{font_size}" font-weight="700" text-anchor="middle">{escape(name)}</text>
  <text x="960" y="670" fill="#8f9aa3" font-family="Fira Sans, sans-serif"
        font-size="30" text-anchor="middle">{escape(subtitle)}</text>
</svg>
"""

    output.write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
