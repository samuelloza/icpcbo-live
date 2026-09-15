#!/usr/bin/env python3

from base64 import b64encode
from html import escape
from pathlib import Path
import sys
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET


MAX_LOGO_BYTES = 5 * 1024 * 1024


def pick_font_size(name: str) -> int:
    if len(name) > 28:
        return 64
    if len(name) > 18:
        return 80
    return 100


def logo_markup(url: str) -> str:
    if urlparse(url).scheme not in {"http", "https"}:
        return ""
    try:
        with urlopen(Request(url, headers={"User-Agent": "ICPCBO-Contest-Login/1"}), timeout=5) as response:
            data = response.read(MAX_LOGO_BYTES + 1)
        root = ET.fromstring(data)
        if len(data) > MAX_LOGO_BYTES or root.tag.rsplit("}", 1)[-1] != "svg":
            return ""
    except (OSError, ValueError, ET.ParseError):
        return ""
    encoded = b64encode(data).decode("ascii")
    return (f'<image x="660" y="180" width="600" height="300" '
            f'preserveAspectRatio="xMidYMid meet" href="data:image/svg+xml;base64,{encoded}"/>')


def main() -> None:
    name = sys.argv[1].strip() or "Equipo"
    team_id = sys.argv[2].strip()
    logo = logo_markup(sys.argv[3]) if len(sys.argv) > 4 else ""
    output = Path(sys.argv[4] if len(sys.argv) > 4 else sys.argv[3])
    output.parent.mkdir(parents=True, exist_ok=True)

    subtitle = f"Equipo: {team_id}" if team_id else "ICPC Bolivia"
    font_size = pick_font_size(name)

    svg = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <rect width="1920" height="1080" fill="#000000"/>
  {logo or '<text x="960" y="460" fill="#f4f0dd" font-family="Share, Fira Sans, sans-serif" font-size="36" text-anchor="middle" letter-spacing="8">ICPC BOLIVIA</text>'}
  <text x="960" y="590" fill="#ffffff" font-family="Fira Sans, sans-serif"
        font-size="{font_size}" font-weight="700" text-anchor="middle">{escape(name)}</text>
  <text x="960" y="670" fill="#8f9aa3" font-family="Fira Sans, sans-serif"
        font-size="30" text-anchor="middle">{escape(subtitle)}</text>
</svg>
"""

    output.write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
