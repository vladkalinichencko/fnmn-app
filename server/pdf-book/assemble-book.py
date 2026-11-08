"""Build a Markdown book from grounded OCR and a born-digital PDF."""

import argparse
from collections import Counter
from difflib import SequenceMatcher
import json
from pathlib import Path
import re
import sys
import unicodedata

import pymupdf

sys.path.insert(0, str(Path(__file__).resolve().parent))
from grounding import blocks as grounding_blocks  # noqa: E402
from math_issues import math_issues  # noqa: E402


LABEL = re.compile(r'\(([A-Za-zε∞]?\d+(?:\.\d+)+)\)[,.]?')


def normalized(text):
    text = re.sub(r'\\\(.*?\\\)|\\\[.*?\\\]', ' MATH ', text, flags=re.S)
    text = unicodedata.normalize('NFKC', text).casefold()
    text = re.sub(r'(?<=\w)-\s+(?=\w)', '', text)
    return ' '.join(re.findall(r'[a-z]{2,}', text))


def similarity(left, right):
    return SequenceMatcher(None, normalized(left).split(), normalized(right).split(), autojunk=False).ratio()


def heading_similarity(left, right):
    def clean(value):
        value = re.sub(r'K(?:\^\{(?:\\star|\*)\}|\*)\s*=\s*0', 'K star 0', value)
        value = re.sub(r'(?:\\\(|\$)\s*K star 0\s*(?:\\\)|\$)', 'K star 0', value)
        return re.sub(
            r'^(?:(?:\$\\infty(?:\.\d+)*\$|\\\(\s*\\infty\s*\\\))(?:\.\d+)*\s*|(?:\d+(?:\.\d+)*|[A-Z](?:\.\d+)*|∞(?:\.\d+)*|(?:\.\d+)+)\s+)',
            '', value)
    return similarity(clean(left), clean(right))


def scale(bbox, page):
    return [bbox[0] / page.rect.width * 1000, bbox[1] / page.rect.height * 1000,
            bbox[2] / page.rect.width * 1000, bbox[3] / page.rect.height * 1000]


def read_ocr(text):
    return grounding_blocks(text)


def pdf_blocks(page):
    result, sizes = [], Counter()
    for raw in page.get_text('dict')['blocks']:
        if raw['type'] != 0:
            continue
        items = [span for line in raw['lines'] for span in line['spans']]
        for span in items:
            sizes[round(span['size'], 1)] += len(span['text'])
        text = '\n'.join(''.join(s['text'] for s in line['spans']) for line in raw['lines'])
        math_chars = sum(len(span['text']) for span in items
                         if 'Math' in span['font'] or span['font'].startswith('MSBM'))
        result.append({'text': text, 'bbox': scale(raw['bbox'], page), 'spans': items,
                       'math_ratio': math_chars / max(1, len(text))})
    common = [size for size, count in sizes.items() if 9 <= size <= 12 and count >= 40]
    return result, max(common) if common else (sizes.most_common(1)[0][0] if sizes else 0)


def vertical_overlap(left, right):
    intersection = max(0, min(left[3], right[3]) - max(left[1], right[1]))
    return intersection / max(1, min(left[3] - left[1], right[3] - right[1]))


def merged(blocks):
    return {'text': ' '.join(block['text'] for block in blocks),
            'bbox': [min(block['bbox'][0] for block in blocks), min(block['bbox'][1] for block in blocks),
                     max(block['bbox'][2] for block in blocks), max(block['bbox'][3] for block in blocks)]}


def align(pdf, ocr):
    """Order-preserving alignment, including split and joined layout blocks."""
    rows, cols = len(pdf), len(ocr)
    scores = [[-float('inf')] * (cols + 1) for _ in range(rows + 1)]
    steps = [[None] * (cols + 1) for _ in range(rows + 1)]
    scores[0][0] = 0
    for i in range(rows + 1):
        for j in range(cols + 1):
            if i < rows and scores[i][j] - .25 > scores[i + 1][j]:
                scores[i + 1][j], steps[i + 1][j] = scores[i][j] - .25, (i, j, 0, 0, 'pdf_only')
            if j < cols and scores[i][j] - .25 > scores[i][j + 1]:
                scores[i][j + 1], steps[i][j + 1] = scores[i][j] - .25, (i, j, 0, 0, 'ocr_only')
            for pdf_count in range(1, min(5, rows - i) + 1):
                left = merged(pdf[i:i + pdf_count])
                for ocr_count in range(1, min(3, cols - j) + 1):
                    right = merged(ocr[j:j + ocr_count])
                    match = similarity(left['text'], right['text'])
                    value = (scores[i][j] + match + .25 * vertical_overlap(left['bbox'], right['bbox'])
                             - .04 * (pdf_count + ocr_count - 2))
                    ni, nj = i + pdf_count, j + ocr_count
                    if value > scores[ni][nj]:
                        scores[ni][nj], steps[ni][nj] = value, (i, j, pdf_count, ocr_count, match)
    pairs, i, j = [], rows, cols
    while i or j:
        previous = steps[i][j]
        if previous is None:
            previous = (i - 1, j, 0, 0, 'pdf_only') if i else (i, j - 1, 0, 0, 'ocr_only')
        pi, pj, pdf_count, ocr_count, kind = previous
        if isinstance(kind, float):
            pairs.append({'pdf': list(range(pi, pi + pdf_count)),
                          'ocr': list(range(pj, pj + ocr_count)), 'score': round(kind, 3)})
        i, j = pi, pj
    return list(reversed(pairs))


def word_coverage(left, right):
    left, right = normalized(left).split(), normalized(right).split()
    if not left:
        return 1.0
    matches = SequenceMatcher(None, left, right, autojunk=False).get_matching_blocks()
    return sum(match.size for match in matches) / len(left)


def contiguous_coverage(left, right):
    left, right = normalized(left).split(), normalized(right).split()
    if not left:
        return 1.0
    matches = SequenceMatcher(None, left, right, autojunk=False).get_matching_blocks()
    return max(match.size for match in matches) / len(left)


def is_heading(block, body_size):
    spans = [span for span in block['spans'] if span['text'].strip()]
    return bool(spans and (max(span['size'] for span in spans) > body_size + .5
                           or all('Bold' in span['font'] for span in spans)))


def is_multicolumn(blocks):
    left = sum(block['bbox'][2] < 540 and len(normalized(block['text']).split()) >= 3 for block in blocks)
    right = sum(block['bbox'][0] > 460 and len(normalized(block['text']).split()) >= 3 for block in blocks)
    return left >= 4 and right >= 4


def clean_pdf_text(text):
    text = unicodedata.normalize('NFKC', text)
    text = re.sub(r'(?<=\w)-\s+(?=\w)', '', text)
    return re.sub(r'\s+', ' ', text).strip()


def footnote_definition(label, text):
    lines = text.strip().splitlines()
    if not lines:
        return f'[^{label}]:'
    continuation = '\n'.join(f'    {line}' if line else '' for line in lines[1:])
    return f'[^{label}]: {lines[0]}' + (f'\n{continuation}' if continuation else '')


def missing_footnote_targets(pdf, prose, textual, pairs, notes, note_blocks, body_size):
    present = {match[1] for block in textual
               for match in re.finditer(r'\\\(\s*\^\{(\d+)\}\s*\\\)', block['text'])}
    targets, missing = {}, []
    prose_index = {id(block): index for index, block in enumerate(prose)}
    for note in notes:
        number = note['number']
        if number in present:
            continue
        candidates = []
        for block in pdf:
            if id(block) in note_blocks:
                continue
            spans = [span for span in block['spans'] if span['text'].strip()]
            body_baselines = [span['origin'][1] for span in spans if span['size'] >= body_size - .5]
            if any(index and 'Roman' in spans[index - 1]['font'] and span['text'].strip() == number
                   and body_size - 3.5 <= span['size'] <= body_size - 1.5
                   and ((body_baselines and block['math_ratio'] < .30
                         and span['origin'][1] <= min(body_baselines,
                                                     key=lambda y: abs(y - span['origin'][1])) - 2)
                        or spans[index - 1]['text'].rstrip().endswith(('.', '?', '!', ',', ')', ']')))
                   for index, span in enumerate(spans)):
                candidates.append(block)
        if len(candidates) != 1:
            missing.append(number)
            continue
        index = prose_index.get(id(candidates[0]))
        pair = next((pair for pair in pairs if index in pair['pdf']), None) if index is not None else None
        choices = [textual[i] for i in pair['ocr']] if pair else textual
        if not choices:
            missing.append(number)
            continue
        target = min(choices, key=lambda block: abs(block['bbox'][1] - candidates[0]['bbox'][1]))
        targets.setdefault(id(target), []).append(number)
    return targets, missing


def latex(text):
    """Rewrite only spellings that have one legal result. Brace repairs stay issues."""

    def inner(value):
        value = value.replace('∞', r'\infty').replace(
            r'\begin{align*}', r'\begin{aligned}').replace(r'\end{align*}', r'\end{aligned}')
        return value.replace(r'\begin{aligned}=&', r'\begin{aligned}&')

    text = re.sub(r'\\\[(.*?)\\\]', lambda match: f'\n$$\n{inner(match[1]).strip()}\n$$\n', text, flags=re.S)
    text = re.sub(r'\$\$(.*?)\$\$', lambda match: f'\n$$\n{inner(match[1]).strip()}\n$$\n', text, flags=re.S)
    return re.sub(r'\\\((.*?)\\\)', lambda match: f'${inner(match[1]).strip()}$', text, flags=re.S)


def equation_labels(page, equations):
    labels = []
    for x0, y0, _, y1, text, *_ in page.get_text('words'):
        match = LABEL.fullmatch(text)
        if not match or x0 < page.rect.width * .68:
            continue
        y = (y0 + y1) / 2 / page.rect.height * 1000
        candidates = [i for i, block in enumerate(equations)
                      if block['bbox'][1] - 8 <= y <= block['bbox'][3] + 8]
        if len(candidates) == 1:
            labels.append((candidates[0], match[1]))
    return dict(labels)


def add_label(text, label):
    compact = re.sub(r'[^A-Za-zε∞0-9.]', '', text.replace(r'\infty', '∞'))
    if re.sub(r'[^A-Za-zε∞0-9.]', '', label) in compact:
        return text, False
    marker = r'\quad (' + label.replace('∞', r'\infty') + ')'
    return (text.replace(r'\]', marker + r' \]', 1), True) if r'\]' in text else (text + ' ' + marker, True)


def footnotes(pdf, body_size):
    groups, current = [], None
    for index, block in enumerate(pdf):
        spans = [span for span in block['spans'] if span['text'].strip()]
        first, second = (spans + [None, None])[:2]
        number = re.match(r'^(\d+)', first['text']) if first else None
        starts = bool(number and second and first['size'] <= body_size - 2
                      and second['size'] >= body_size - 2.5 and 'Roman' in second['font']
                      and re.match(r'^[A-Z]', second['text']) and block['bbox'][1] > 400)
        if starts:
            current = {'number': number[1], 'indices': [index],
                       'text': block['text'][len(number[1]):].strip()}
            groups.append(current)
        elif current and block['bbox'][1] < 835:
            current['indices'].append(index)
            current['text'] += ' ' + block['text'].strip()
        else:
            current = None
    split_groups = []
    for group in groups:
        text = unicodedata.normalize('NFKC', group['text'])
        text = re.sub(r'(?<=\w)-\s+(?=\w)', '', text)
        text = re.sub(r'\s+', ' ', text).strip()
        starts = list(re.finditer(r'(?<=[.!?])\s+(\d+)(?=[A-Z])', text))
        positions = [(0, group['number'])] + [(match.end(), match[1]) for match in starts]
        ends = [match.start() for match in starts] + [len(text)]
        for (start, number), end in zip(positions, ends):
            value = text[start:end].strip()
            split_groups.append({'number': number, 'indices': group['indices'], 'text': value,
                                 'needs_ocr': (bool(re.search(
                                     r'[\x00-\x08\x0b\x0c\x0e-\x1f\uf8eb-\uf8ff]', value))
                                               or any(pdf[index]['math_ratio'] > .03
                                                      for index in group['indices']))})
    return split_groups


def extract_region(page, bbox, name, assets, padding=0):
    x0, y0, x1, y1 = bbox
    clip = pymupdf.Rect(x0 / 1000 * page.rect.width, y0 / 1000 * page.rect.height,
                        x1 / 1000 * page.rect.width, y1 / 1000 * page.rect.height)
    clip = pymupdf.Rect(clip.x0 - padding, clip.y0 - padding, clip.x1 + padding, clip.y1 + padding)
    page.get_pixmap(clip=clip, dpi=180, alpha=False).save(assets / name)
    return name


def extract_image(page, block, number, index, assets):
    name = extract_region(page, block['bbox'], f'page-{number}-image-{index}.png', assets)
    return f'![Figure from PDF page {number}](assets/{name})'


class PageBuild:
    def __init__(self, page, number, ocr, outline, level, assets, repeated_margins, footnote_overrides, formula_overrides):
        self.page = page
        self.number = number
        self.ocr = ocr
        self.outline = outline
        self.level = level
        self.assets = assets
        self.repeated_margins = repeated_margins
        self.footnote_overrides = footnote_overrides
        self.formula_overrides = formula_overrides

    def run(self):
        pdf, body_size = pdf_blocks(self.page)
        self.pdf = pdf
        self.multicolumn = is_multicolumn(pdf)
        self.notes = footnotes(pdf, body_size)
        note_blocks = {id(pdf[i]) for note in self.notes for i in note['indices']}
        note_regions = [merged([pdf[index] for index in note['indices']])['bbox'] for note in self.notes]
        self.prose = [block for block in pdf if id(block) not in note_blocks and not is_heading(block, body_size)
                      and len(normalized(block['text']).split()) >= 5]

        def in_footnote(block):
            return any(vertical_overlap(block['bbox'], region) >= .5 for region in note_regions)

        self.textual = [block for block in self.ocr if block['kind'] in {'text', 'figure_title'} and not in_footnote(block)]
        self.pairs = align(self.prose, self.textual)
        self.paired_pdf = {index for pair in self.pairs for index in pair['pdf']}
        self.note_numbers = {note['number'] for note in self.notes}
        self.reference_targets, self.missing_references = missing_footnote_targets(
            pdf, self.prose, self.textual, self.pairs, self.notes, note_blocks, body_size)
        equations = [block for block in self.ocr if block['kind'] == 'equation']
        self.labels = equation_labels(self.page, equations)
        self.in_footnote = in_footnote
        self.content = []
        self.changes = []
        self.equation_issues = []
        self.image_index = 0
        self.render()
        self.definitions = self.footnote_definitions()
        self.unmatched = self.restore_prose()
        return self.finish()

    def render(self):
        used_outline = set()
        equation_index = 0
        for block in self.ocr:
            kind, bbox, text = block['kind'], block['bbox'], block['text']
            if self.in_footnote(block):
                self.changes.append({'type': 'removed_ocr_footnote', 'text': text})
                continue
            margin = bbox[3] < 100 or bbox[1] > 930
            if kind in {'header', 'footer'} or (kind == 'text' and margin and self.repeated_margins[normalized(text)] >= 3):
                self.changes.append({'type': 'removed_margin', 'text': text})
                continue
            if kind == 'equation':
                override = self.formula_overrides.get(f'{self.number}:{equation_index + 1}')
                if override:
                    text = override
                    self.changes.append({'type': 'replaced_formula', 'equation': equation_index + 1})
                if equation_index in self.labels:
                    text, added = add_label(text, self.labels[equation_index])
                    if added:
                        self.changes.append({'type': 'restored_equation_label', 'label': self.labels[equation_index]})
                equation_index += 1
            elif kind == 'image':
                self.image_index += 1
                text = extract_image(self.page, block, self.number, self.image_index, self.assets)
            elif kind in {'title', 'sub_title'}:
                title = re.sub(r'^#+\s*', '', text).strip()
                candidates = [(heading_similarity(title, entry[1]), i, entry) for i, entry in enumerate(self.outline)
                              if entry[2] == self.number and i not in used_outline]
                score, index, entry = max(candidates, default=(0, -1, None))
                if score >= .90:
                    self.level = entry[0]
                    used_outline.add(index)
                    if self.level == 1:
                        title = entry[1]
                    heading_level = self.level
                elif re.fullmatch(r'(?:Chapter\s+\S+|Appendix\s+[A-Z])', title, re.I):
                    continue
                else:
                    heading_level = min(self.level + 1, 6) if self.level else 2
                text = '#' * heading_level + ' ' + title
            for note_number in self.reference_targets.get(id(block), []):
                text += rf' \(^{{{note_number}}}\)'
                self.changes.append({'type': 'restored_footnote_reference', 'number': note_number})
            for note_number in self.note_numbers:
                text = re.sub(r'\\\(\s*\^\{' + re.escape(note_number) + r'\}\s*\\\)',
                              f'[^p{self.number}-{note_number}]', text)
            rendered = latex(text)
            if kind == 'equation':
                defects = math_issues(rendered)
                if defects:
                    image = extract_region(
                        self.page, bbox, f'page-{self.number}-formula-{equation_index}.png', self.assets, padding=3)
                    for defect in defects:
                        defect['image'] = f'assets/{image}'
                        defect['equation'] = equation_index
                    self.equation_issues.extend(defects)
            self.content.append((bbox[1], rendered))

    def footnote_definitions(self):
        definitions = []
        for note in self.notes:
            override = self.footnote_overrides.get(f'{self.number}:{note["number"]}')
            if override or not note['needs_ocr']:
                definitions.append(footnote_definition(
                    f'p{self.number}-{note["number"]}', latex(override) if override else note['text']))
        return definitions

    def restore_prose(self):
        page_ocr = ' '.join(block['text'] for block in self.textual)
        unmatched = []
        if not self.multicolumn:
            for index, block in enumerate(self.prose):
                if index in self.paired_pdf or word_coverage(block['text'], page_ocr) >= .75:
                    continue
                safe = (block['math_ratio'] < .08
                        and not re.search(r'[\x00-\x08\x0b\x0c\x0e-\x1f\uf8eb-\uf8ff]', block['text']))
                if safe and contiguous_coverage(block['text'], page_ocr) < .45:
                    text = clean_pdf_text(block['text'])
                    self.content.append((block['bbox'][1], text))
                    self.changes.append({'type': 'restored_pdf_prose', 'text': text, 'bbox': block['bbox']})
                else:
                    unmatched.append({'text': block['text'], 'bbox': block['bbox'],
                                      'coverage': round(word_coverage(block['text'], page_ocr), 3),
                                      'math_ratio': round(block['math_ratio'], 3)})
        return unmatched

    def finish(self):
        self.content.sort(key=lambda item: item[0])
        weak = [] if self.multicolumn else [
            {**pair, 'pdf_text': merged([self.prose[i] for i in pair['pdf']])['text'],
             'ocr_text': merged([self.textual[i] for i in pair['ocr']])['text']}
            for pair in self.pairs if pair['score'] < .60]
        markdown = '\n\n'.join([*(text for _, text in self.content), *self.definitions])
        issues = syntax_issues(markdown)
        known_formulas = {issue['formula'] for issue in self.equation_issues}
        issues.extend(self.equation_issues)
        issues.extend(issue for issue in math_issues(markdown)
                      if not any(issue['formula'] in formula or formula in issue['formula']
                                 for formula in known_formulas))
        issues.extend({'type': 'footnote_reference_missing', 'number': missing}
                      for missing in self.missing_references)
        for note in self.notes:
            key = f'{self.number}:{note["number"]}'
            if not note['needs_ocr'] or key in self.footnote_overrides:
                continue
            blocks = [self.pdf[index] for index in note['indices']]
            bbox = merged(blocks)['bbox']
            image = extract_region(self.page, bbox, f'page-{self.number}-footnote-{note["number"]}.png', self.assets, padding=3)
            issues.append({'type': 'footnote_needs_ocr', 'number': note['number'],
                           'text': note['text'], 'bbox': bbox, 'image': f'assets/{image}'})
        return (markdown,
                {'page': self.number, 'alignment': self.pairs, 'weak_matches': weak, 'unmatched_pdf': self.unmatched,
                 'changes': self.changes, 'footnotes': self.notes, 'images': self.image_index, 'issues': issues}, self.level)


def build_page(page, number, ocr, outline, level, assets, repeated_margins, footnote_overrides, formula_overrides):
    return PageBuild(page, number, ocr, outline, level, assets, repeated_margins, footnote_overrides, formula_overrides).run()


def syntax_issues(text):
    issues = []
    outside_math = re.sub(r'\$\$.*?\$\$|(?<!\$)\$(?!\$).*?(?<!\$)\$(?!\$)', '', text, flags=re.S)
    bare = sorted(set(re.findall(r'\\[A-Za-z]+', outside_math)))
    if bare:
        issues.append({'type': 'bare_latex', 'commands': bare[:12]})
    if len(re.findall(r'(?<!\\)\$', text)) % 2:
        issues.append({'type': 'unbalanced_math_delimiter'})
    begins, ends = Counter(re.findall(r'\\begin\{([^}]+)\}', text)), Counter(re.findall(r'\\end\{([^}]+)\}', text))
    if begins != ends:
        issues.append({'type': 'unbalanced_environment', 'begin': begins, 'end': ends})
    return issues


def repetition_issue(text):
    tokens = re.findall(r'\\[A-Za-z]+|\S+', text)
    token, count = Counter(tokens).most_common(1)[0] if tokens else ('', 0)
    return {'type': 'repetition', 'token': token, 'count': count} if count >= 64 else None


def validate(markdown, output, expected_pages, outline):
    references = set(re.findall(r'\[\^(p\d+-\d+)\](?!:)', markdown))
    definitions = set(re.findall(r'^\[\^(p\d+-\d+)\]:', markdown, re.M))
    images = re.findall(r'!\[[^]]*\]\(([^)]+)\)', markdown)
    errors = []
    if markdown.count('<!-- PDF page ') != expected_pages:
        errors.append('page_count')
    if references != definitions:
        errors.append('footnote_links')
    if any(not (output.parent / image).exists() for image in images):
        errors.append('missing_images')
    if '<|ref|>' in markdown or any(ord(char) < 32 and char not in '\n\t\r' for char in markdown):
        errors.append('raw_ocr_artifacts')
    headings_by_page = {}
    for chunk in re.split(r'(?=<!-- PDF page \d+ -->)', markdown):
        marker = re.match(r'<!-- PDF page (\d+) -->', chunk)
        if marker:
            headings_by_page[int(marker[1])] = [(len(prefix), title) for prefix, title
                                                in re.findall(r'^(#+) (.+)$', chunk, re.M)]
    outline_matches = sum(any(level == found_level and heading_similarity(title, found_title) >= .90
                              for found_level, found_title in headings_by_page.get(page, []))
                          for level, title, page in outline)
    if outline_matches != len(outline):
        errors.append('outline_headings')
    return {'pages': expected_pages, 'headings': len(re.findall(r'^#+ ', markdown, re.M)),
            'outline_entries': len(outline), 'outline_matches': outline_matches,
            'images': len(images), 'footnotes': len(definitions), 'errors': errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('pdf', type=Path)
    parser.add_argument('ocr', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--replacements', type=Path)
    parser.add_argument('--footnote-overrides', type=Path)
    parser.add_argument('--formula-overrides', type=Path)
    parser.add_argument('--exclude-pages', type=int, nargs='+', default=[])
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    assets = args.output.parent / 'assets'
    assets.mkdir(exist_ok=True)
    footnote_overrides = (json.loads(args.footnote_overrides.read_text())
                          if args.footnote_overrides and args.footnote_overrides.exists() else {})
    formula_overrides = (json.loads(args.formula_overrides.read_text())
                         if args.formula_overrides and args.formula_overrides.exists() else {})
    with pymupdf.open(args.pdf) as document:
        outline = document.get_toc()
        raw, metrics = {}, {}
        for number in range(1, len(document) + 1):
            source = args.replacements if args.replacements and (args.replacements / f'page-{number}.md').exists() else args.ocr
            raw[number] = (source / f'page-{number}.md').read_text()
            metrics[number] = json.loads((source / f'page-{number}.json').read_text())
        margins = Counter(normalized(block['text']) for text in raw.values() for block in read_ocr(text)
                          if block['kind'] == 'text' and (block['bbox'][3] < 100 or block['bbox'][1] > 930))
        pages, audits, level = [], [], 0
        for number, page in enumerate(document, 1):
            if number in args.exclude_pages:
                continue
            text, audit, level = build_page(page, number, read_ocr(raw[number]), document.get_toc(),
                                            level, assets, margins, footnote_overrides, formula_overrides)
            audit['finish_reason'] = metrics[number]['finish_reason']
            repetition = repetition_issue(raw[number])
            if repetition:
                audit['issues'].append(repetition)
            pages.append(f'<!-- PDF page {number} -->\n\n{text}')
            audits.append(audit)
    markdown = '\n\n'.join(pages) + '\n'
    args.output.write_text(markdown)
    args.output.with_suffix('.audit.json').write_text(json.dumps(audits, ensure_ascii=False, indent=2) + '\n')
    candidates = [{'page': audit['page'], 'issues': audit['issues'],
                   'weak_matches': audit['weak_matches'], 'unmatched_pdf': audit['unmatched_pdf']}
                  for audit in audits if audit['issues'] or audit['weak_matches'] or audit['unmatched_pdf']]
    args.output.with_suffix('.candidates.json').write_text(json.dumps(candidates, ensure_ascii=False, indent=2) + '\n')
    validation = validate(markdown, args.output, len(pages), outline)
    args.output.with_suffix('.validation.json').write_text(json.dumps(validation, indent=2) + '\n')
    if validation['errors']:
        raise RuntimeError(f'book validation failed: {validation["errors"]}')
    print(f'{args.output}: {len(pages)} pages, {sum(a["images"] for a in audits)} images, '
          f'{sum(len(a["footnotes"]) for a in audits)} footnotes, '
          f'{sum(len(a["issues"]) + len(a["weak_matches"]) + len(a["unmatched_pdf"]) for a in audits)} audit items')


if __name__ == '__main__':
    main()
