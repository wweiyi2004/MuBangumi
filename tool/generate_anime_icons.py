"""Author repository SVG icons using the pinned SDK and installed icon font.

Usage: python tool/generate_anime_icons.py --flutter-root <Get-MuFlutterRoot>
Requires fontTools for authoring only; it is not a client dependency.
"""
from pathlib import Path
import argparse
import json
import re
from urllib.parse import unquote, urlparse
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen

ROOT = Path(__file__).resolve().parents[1]
SHAPES = {
    'tv': '<rect x="3" y="6" width="18" height="14" rx="4"/><path d="m6 6-2-3 6 3m8 0 2-3-6 3M8 10l7 4-7 3z"/>',
    'collection': '<path d="M5 5h12a3 3 0 0 1 3 3v13l-5-3-5 3V8a3 3 0 0 0-3-3H4V2h12"/><path d="m5 11 1 2 2 1-2 1-1 2-1-2-2-1 2-1z"/>',
    'discover': '<circle cx="12" cy="12" r="9"/><path d="m15 7-2 6-6 4 3-7zM19 2v4m-2-2h4"/>',
    'chat': '<path d="M5 4h14a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3h-8l-6 3v-3a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3z"/><path d="M7 10v1m5-1v1m5-1v1M8 15h8"/>',
    'profile': '<path d="m4 9 1-6 5 4h4l5-4 1 6v5a7 7 0 0 1-7 7h-2a7 7 0 0 1-7-7zM8 12v1m8-1v1m-6 3 2 1 2-1M1 13l3 1m19-1-3 1"/>',
    'group': '<path d="M3 12 4 6l4 3 4-3 1 6v2a5 5 0 0 1-10 0zM14 10l1-5 3 2 3-2 1 5v2a4 4 0 0 1-8 0M5 19h6m5-2h4M6 13h.01m4 0h.01"/>',
    'search': '<circle cx="10" cy="10" r="7"/><path d="m15 15 6 6M9 6v3m-2-1.5h4M21 3v4m-2-2h4"/>',
    'calendar': '<rect x="3" y="5" width="18" height="17" rx="4"/><path d="M7 2v6m10-6v6M3 10h18m-9 3 1 2 3 1-2 2 .2 3-2.2-1.5L9 21l.2-3L7 16l3-1z"/>',
    'bell': '<path d="M5 16h14l-2-3V9a5 5 0 0 0-10 0v4zM9 20q3 3 6 0M8 5 6 2l5 2m5 1 2-3-5 2"/>',
    'edit': '<path d="m4 20 2-7L17 2l5 5-11 11zM6 13l5 5M3 22h18M17 4l3 3M3 3v4M1 5h4"/>',
    'send': '<path d="m2 11 20-8-7 19-4-8zM11 14 22 3M2 17v4m-2-2h4"/>',
    'share': '<circle cx="6" cy="12" r="3"/><circle cx="18" cy="5" r="3"/><circle cx="18" cy="19" r="3"/><path d="m9 10 6-3M9 14l6 3M12 1v3m-1.5-1.5h3"/>',
    'heart': '<path d="M12 21S2 15 2 8a5 5 0 0 1 10-1 5 5 0 0 1 10 1c0 7-10 13-10 13zM6 8v2m12-2v2"/>',
    'download': '<path d="M6 17a5 5 0 0 1-1-10 7 7 0 0 1 13-1 5 5 0 0 1 2 10M12 9v13m-4-4 4 4 4-4"/>',
    'settings': '<path d="M12 3c4-5 7 0 5 4 5-2 8 4 3 6 4 4 0 8-5 6-1 5-7 5-7 0-5 2-9-3-5-6-5-2-2-8 3-6-2-4 1-9 6-4z"/><circle cx="12" cy="12" r="3"/>',
    'font': '<path d="M3 20 9 4l6 16M6 13h6M16 8h6m-3 0v12M18 2v3m-1.5-1.5h3"/>',
    'chart': '<path d="M3 3v18h18M6 16l5-6 4 3 6-8"/><path d="m20 1 .8 2.2L23 4l-2.2.8L20 7l-.8-2.2L17 4l2.2-.8z"/>',
    'scan': '<path d="M3 8V3h5m8 0h5v5M3 16v5h5m8 0h5v-5M8 10l1-3 3 2 3-2 1 3v5H8zM10 12h.01m4 0h.01"/>',
    'refresh': '<path d="M20 9A8 8 0 0 0 5 6L2 9m0-6v6h6M4 15a8 8 0 0 0 15 3l3-3m0 6v-6h-6"/>',
    'staff': '<rect x="3" y="6" width="18" height="16" rx="3"/><path d="M9 2h6v7H9zM7 13h.01m10 0h.01M7 17h10"/>',
    'blog': '<path d="M12 5Q7 2 2 5v16q5-3 10 0 5-3 10 0V5q-5-3-10 0v16M5 9h4m-4 4h4m6-4h4m-4 4h4"/>',
}

def design(name):
    for pattern, key in [
        ('qr_code|crop_free', 'scan'), ('calendar|date_range|event_', 'calendar'),
        ('notification|bell', 'bell'), ('person_add|people|group|person_3', 'group'),
        ('person|account_circle|face', 'profile'), ('library|bookmark|collections_bookmark', 'collection'),
        ('play_circle|movie|live_tv|smart_display|video', 'tv'), ('search', 'search'),
        ('explore|compass', 'discover'), ('chat|forum|message|comment', 'chat'),
        ('ios_share|share_', 'share'), ('send|paperplane', 'send'), ('favorite|heart', 'heart'),
        ('download', 'download'), ('settings|tune|gear', 'settings'), ('text_fields|font', 'font'),
        ('chart|trending', 'chart'), ('refresh|sync', 'refresh'), ('badge', 'staff'),
        ('edit|create_|draw|pencil', 'edit'), ('article|menu_book|book', 'blog'),
    ]:
        if re.search(pattern, name): return SHAPES[key]
    return None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--flutter-root', type=Path, required=True)
    args = parser.parse_args()
    pinned = json.loads((ROOT/'tool/toolchain.json').read_text())
    sdk = json.loads((args.flutter_root/'bin/cache/flutter.version.json').read_text())
    if sdk['frameworkVersion'] != pinned['flutter'] or sdk['frameworkRevision'] != pinned['flutterFrameworkRevision']:
        raise SystemExit('Use the project-pinned official Flutter SDK via tool/toolchain.ps1.')
    config = json.loads((ROOT/'.dart_tool/package_config.json').read_text())
    cupertino = next(item for item in config['packages'] if item['name'] == 'cupertino_icons')
    font_root = unquote(urlparse(cupertino['rootUri']).path) if ':' in cupertino['rootUri'] else cupertino['rootUri']
    if re.match(r'^/[a-zA-Z]:/', font_root): font_root = font_root[1:]
    cupertino_root = Path(font_root)
    sources = [
        ('Icons', 'MaterialIcons', args.flutter_root/'packages/flutter/lib/src/material/icons.dart', args.flutter_root/'bin/cache/artifacts/material_fonts/materialicons-regular.otf'),
        ('CupertinoIcons', 'CupertinoIcons', args.flutter_root/'packages/flutter/lib/src/cupertino/icons.dart', cupertino_root/'assets/CupertinoIcons.ttf'),
    ]
    used = set()
    for path in (ROOT/'lib').rglob('*.dart'):
        used.update(re.findall(r'\b(Icons|CupertinoIcons)\.(\w+)', path.read_text(encoding='utf-8-sig')))
    assets = ROOT/'assets/icons'
    assets.mkdir(parents=True, exist_ok=True)
    mapping = {}
    custom = set()
    for class_name, family, definitions, font_path in sources:
        text = definitions.read_text()
        points = {name:int(point,16) for name,point in re.findall(r'static const IconData (\w+) = IconData\(\s*(0x[\da-fA-F]+)', text)}
        # SDK aliases (e.g. Cupertino heart) still use existing code points.
        for alias,target in re.findall(r'static const IconData (\w+) = (\w+);', text):
            if target in points: points[alias] = points[target]
        font = TTFont(font_path)
        glyphs = font.getGlyphSet()
        cmap = font.getBestCmap()
        for _,name in sorted(item for item in used if item[0] == class_name):
            point = points.get(name)
            if point is None or point not in cmap: continue
            key = f'{family}:{point}'
            filename = f'{family.lower()}_{point:x}.svg'
            drawing = design(name)
            if key in custom: continue
            if drawing:
                custom.add(key)
                body = f'<g fill="none" stroke="#000" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">{drawing}</g>'
            else:
                glyph = glyphs[cmap[point]]
                bounds = BoundsPen(glyphs); glyph.draw(bounds)
                pen = SVGPathPen(glyphs); glyph.draw(pen)
                if not bounds.bounds: continue
                x0,y0,x1,y1 = bounds.bounds
                scale = 20/max(x1-x0,y1-y0)
                tx = 12-(x0+x1)*scale/2
                ty = 12+(y0+y1)*scale/2
                body = f'<path fill="#000" d="{pen.getCommands()}" transform="translate({tx:.5f} {ty:.5f}) scale({scale:.5f} {-scale:.5f})"/>'
            (assets/filename).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">{body}</svg>\n', encoding='utf-8')
            mapping[key] = f'assets/icons/{filename}'
    lines = ['// Generated by tool/generate_anime_icons.py using the pinned icon fonts.', 'const animeIconAssets = <String, String>{']
    lines.extend(f"  '{key}': '{value}'," for key,value in sorted(mapping.items()))
    lines.append('};')
    (ROOT/'lib/core/theme/anime_icon_assets.dart').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print(f'Generated {len(mapping)} SVG icons; {len(used)} named references.')

if __name__ == '__main__': main()
