"""Optional manual PDF QA (PyMuPDF): physical sizes, text bounds and index coverage."""
import argparse
import json
import math
import re
from pathlib import Path
import fitz

parser = argparse.ArgumentParser()
parser.add_argument('pdf', type=Path)
parser.add_argument('--catalog', type=Path)
parser.add_argument('--count', type=int, required=True)
parser.add_argument('--slots', type=int, help='Expected number of slots in each of the five tiers')
parser.add_argument('--a3', action='store_true')
parser.add_argument('--mixed', action='store_true', help='Dense A4 cards with an independent A1 board')
parser.add_argument('--board-a3', action='store_true', help='Standard A4 cards with an independent A3 board')
args = parser.parse_args()
document = fitz.open(args.pdf)
paper = (297, 420) if args.a3 else (210, 297)
card = (20, 30) if args.mixed else (36, 54) if args.a3 else (30, 45)
board_paper = (594, 841) if args.mixed else (297, 420) if args.board_a3 else paper
inner = (paper[0] - 20, paper[1] - 47)
per_page = math.floor((inner[0] + 4) / (card[0] + 4)) * math.floor((inner[1] + 4) / (card[1] + 4))
cover_pages = math.ceil(args.count / per_page)
mm = 72 / 25.4
def close(value, target): return abs(value - target * mm) < .05
def is_board(page):
    lines = page.get_text().splitlines()
    return bool(lines) and lines[0].strip().endswith('从夯到拉')
for index, page in enumerate(document):
    sheet = board_paper if is_board(page) else paper
    assert close(page.rect.width, sheet[0]) and close(page.rect.height, sheet[1]), ('paper', index)
    drawings = page.get_drawings()
    assert any(close(d['rect'].width, 50) and close(d['rect'].height, 2) for d in drawings), ('ruler', index)
    for block in page.get_text('dict')['blocks']:
        for line in block.get('lines', []):
            for span in line['spans']:
                box = fitz.Rect(span['bbox'])
                assert page.rect.contains(box), ('text outside page', index, span['text'])
cover_rects = sum(sum(close(d['rect'].width, card[0]) and close(d['rect'].height, card[1])
                      for d in document[index].get_drawings()) for index in range(cover_pages))
assert cover_rects == args.count, ('cover count', cover_rects)
card_numbers = {int(match.group(1)) for page in list(document)[:cover_pages]
                for line in page.get_text().splitlines()
                if (match := re.match(r'^#(\d{3,})', line.strip()))}
assert card_numbers == set(range(1, args.count + 1)), ('missing card captions', sorted(set(range(1, args.count + 1)) - card_numbers))
assert any(close(d['rect'].width, card[0] + 2) and close(d['rect'].height, card[1] + 2)
           for d in document[cover_pages].get_drawings()), 'board slots'
board_slots = 0
board_pages = 0
for page in document:
    if not is_board(page):
        continue
    board_pages += 1
    for drawing in page.get_drawings():
        box = drawing['rect']
        if close(box.width, card[0] + 2) and close(box.height, card[1] + 2):
            board_slots += 1
            assert box.x0 >= 10 * mm - .1 and box.x1 <= page.rect.width - 10 * mm + .1, 'slot horizontal overflow'
            assert box.y0 >= 24 * mm - .1 and box.y1 <= page.rect.height - 23 * mm + .1, 'slot vertical overflow'
if args.slots is not None:
    assert board_slots == args.slots * 5, ('board slot count', board_slots)
if args.catalog:
    entries = json.loads(args.catalog.read_text(encoding='utf-8'))['entries'][:args.count]
    text = re.sub(r'\s+', '', ''.join(page.get_text() for page in document if '编号目录' in page.get_text()))
    missing = [entry['id'] for entry in entries if re.sub(r'\s+', '', entry['title']) not in text]
    assert not missing, ('index titles absent or clipped', missing)
print(json.dumps({'pages': len(document), 'paper_mm': paper, 'board_paper_mm': board_paper, 'cover_cards': cover_rects,
                  'board_pages': board_pages, 'board_slots': board_slots,
                  'card_mm': card, 'slot_mm': [card[0] + 2, card[1] + 2],
                  'ruler_mm': 50, 'text_bounds': 'passed', 'index': 'passed'}, ensure_ascii=True))
