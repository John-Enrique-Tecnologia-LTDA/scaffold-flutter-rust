"""Gera a logo do {= display_name =} nos tamanhos que a web e o Android pedem: favicon PNG, ícones do PWA
(comum e "maskable") e o ícone do launcher do Android.

A logo é a mesma `BrandMark` do app (widgets/page.dart): quadrado de cantos arredondados em
degradê da cor de destaque com a inicial do nome no meio. A fonte é `app/web/favicon.svg`; se ela mudar, rode
de novo:

    python3 app/tool/icones.py

Renderiza com o Chrome em modo headless (CHROME aponta outro executável). Sem dependências.
"""

import os
import subprocess
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
WEB = APP / 'web'
RES = APP / 'android/app/src/main/res'
CHROME = os.environ.get('CHROME', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
SVG = (WEB / 'favicon.svg').read_text()


def maskable(svg: str) -> str:
    """Sem cantos (quem recorta é o sistema) e com a letra recolhida para a zona segura."""
    return svg.replace('rx="143.36"', 'rx="0"').replace('font-size="300"', 'font-size="220"')


def render(svg: str, size: int, out: Path) -> None:
    html = f'<html><body style="margin:0;background:transparent">{svg.replace("<svg ", f"<svg width=\"{size}\" height=\"{size}\" ", 1)}</body></html>'
    with tempfile.TemporaryDirectory() as d:
        page = Path(d) / 'p.html'
        page.write_text(html)
        out.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
             '--default-background-color=00000000', f'--window-size={size},{size}', f'--screenshot={out}', page.as_uri()],
            check=True, capture_output=True,
        )


def main() -> None:
    render(SVG, 32, WEB / 'favicon.png')
    for s in (192, 512):
        render(SVG, s, WEB / f'icons/Icon-{s}.png')
        render(maskable(SVG), s, WEB / f'icons/Icon-maskable-{s}.png')
    for name, k in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
        render(SVG, round(48 * k), RES / f'mipmap-{name}/ic_launcher.png')
    print('ícones gravados em', WEB, 'e', RES)


if __name__ == '__main__':
    main()
