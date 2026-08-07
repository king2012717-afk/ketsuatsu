#!/usr/bin/env python3
"""App Store 用のスクリーンショット（1290 × 2796 / 6.9 インチ）を書き出す。

既定では、実装から起こした画面イメージ（../docs/screens.html 相当の描画）を
端末フレームに入れて書き出す。実機のスクリーンショットに差し替える場合は、
`Store/raw/` に 01.png 〜 06.png を置いてから実行すると、そちらを使う。

    python3 Store/generate_screenshots.py

必要なもの:
    pip3 install playwright pillow
    （このリポジトリの開発環境では Chromium のパスを CHROMIUM_PATH で指定できる）

Linux で実行する場合は日本語フォントを入れておくこと。入っていないと中国語字形の
フォントで描画され、漢字の形が変わってしまう（直・週・録・語 など）。

    apt-get install fonts-noto-cjk
    もしくは Noto Sans JP を /usr/share/fonts/ に置いて fc-cache -f

macOS ではヒラギノが使われるため、そのままで問題ない。
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
SOURCE_HTML = ROOT / "screens-source.html"
RAW_DIR = ROOT / "raw"
OUT_DIR = ROOT / "screenshots"

# App Store Connect の 6.9 インチ枠。1 倍の CSS ピクセル × 3 で書き出す。
CSS_WIDTH, CSS_HEIGHT = 430, 932
SCALE = 3

# (見出し, 添え書き, screens-source.html 内の端末ブロックの番号, 背景)
SHOTS = [
    ("血圧計を撮るだけ。", "上・下・脈拍を自動で読み取ります", 1, "warm"),
    ("撮りためた写真も、\nまとめて記録。", "何枚でも一度に読み取って保存", 2, "warm"),
    ("朝と晩の平均が、\nひと目でわかる。", "直近の傾向と目標達成率をホームに", 0, "cool"),
    ("見たい期間を、\n見たい時間帯で。", "朝・昼・晩・平均を切り替えて確認", 4, "cool"),
    ("測り忘れを、\nやさしく防ぐ。", "1 日に何回でも、曜日ごとにも設定", 5, "warm"),
    ("記録は端末の中に。\nヘルスケアとも連携。", "CSV でも書き出せます", 6, "cool"),
]

BACKGROUNDS = {
    "warm": "linear-gradient(180deg, #FFF3F4 0%, #FFE1E5 100%)",
    "cool": "linear-gradient(180deg, #F6F4FA 0%, #FBE7EA 100%)",
}


def extract_style(html: str) -> str:
    match = re.search(r"<style>(.*?)</style>", html, re.S)
    if not match:
        sys.exit("screens-source.html に <style> が見つかりません")
    return match.group(1)


def extract_symbols(html: str) -> str:
    match = re.search(r'<svg style="display:none".*?</svg>', html, re.S)
    return match.group(0) if match else ""


def extract_devices(html: str) -> list[str]:
    """`<div class="scaler">` のブロックを、開き閉じを数えて取り出す。"""
    blocks: list[str] = []
    needle = '<div class="scaler">'
    index = html.find(needle)
    while index != -1:
        depth = 0
        cursor = index
        while True:
            open_at = html.find("<div", cursor)
            close_at = html.find("</div>", cursor)
            if close_at == -1:
                sys.exit("端末ブロックの閉じタグが見つかりません")
            if open_at != -1 and open_at < close_at:
                depth += 1
                cursor = open_at + 4
            else:
                depth -= 1
                cursor = close_at + 6
                if depth == 0:
                    blocks.append(html[index:cursor])
                    break
        index = html.find(needle, cursor)
    return blocks


def build_page(style: str, symbols: str, devices: list[str]) -> str:
    shots = []
    for order, (headline, sub, device_index, tone) in enumerate(SHOTS, start=1):
        raw = RAW_DIR / f"{order:02d}.png"
        if raw.exists():
            stage = (
                '<div class="device"><img class="raw" '
                f'src="raw/{raw.name}" alt=""></div>'
            )
            stage = f'<div class="scaler" style="--s:.78">{stage}</div>'
        else:
            stage = devices[device_index].replace(
                '<div class="scaler">', '<div class="scaler" style="--s:.78">', 1
            )
        headline_html = headline.replace("\n", "<br>")
        shots.append(
            f'<section class="shot" style="background:{BACKGROUNDS[tone]}">'
            f'<div class="copy"><h2>{headline_html}</h2><p>{sub}</p></div>'
            f'<div class="stage">{stage}</div>'
            f"</section>"
        )

    return f"""<!doctype html>
<html lang="ja" data-theme="light">
<head><meta charset="utf-8"><title>screenshots</title>
<style>
{style}
html, body {{ margin: 0; padding: 0; background: #fff; }}
.shot {{
  width: {CSS_WIDTH}px; height: {CSS_HEIGHT}px; overflow: hidden;
  display: flex; flex-direction: column; align-items: center;
  font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans",
    "Noto Sans JP", "Yu Gothic UI", Meiryo, system-ui, sans-serif;
}}
.copy {{ padding: 54px 34px 0; text-align: center; }}
.copy h2 {{
  margin: 0 0 10px; font-size: 38px; line-height: 1.28; font-weight: 800;
  letter-spacing: -.03em; color: #241B1D;
}}
.copy p {{ margin: 0; font-size: 17px; color: #7D6A6D; }}
.stage {{ margin-top: 26px; }}
.raw {{ width: 390px; height: 844px; border-radius: 44px; display: block; }}
</style>
</head>
<body>
{symbols}
{"".join(shots)}
</body>
</html>"""


def main() -> None:
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        sys.exit("playwright が必要です: pip3 install playwright && playwright install chromium")

    html = SOURCE_HTML.read_text(encoding="utf-8")
    page_html = build_page(extract_style(html), extract_symbols(html), extract_devices(html))

    work = ROOT / "_screenshots.html"
    work.write_text(page_html, encoding="utf-8")
    OUT_DIR.mkdir(exist_ok=True)

    launch: dict = {}
    if chromium := os.environ.get("CHROMIUM_PATH"):
        launch["executable_path"] = chromium

    with sync_playwright() as p:
        browser = p.chromium.launch(**launch)
        page = browser.new_page(
            viewport={"width": CSS_WIDTH, "height": CSS_HEIGHT},
            device_scale_factor=SCALE,
            color_scheme="light",
        )
        page.goto(work.as_uri())
        page.wait_for_timeout(400)

        for index, shot in enumerate(page.query_selector_all(".shot"), start=1):
            path = OUT_DIR / f"{index:02d}.png"
            shot.screenshot(path=str(path))
            print(f"書き出し: {path.relative_to(REPO)}")

        browser.close()

    work.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
