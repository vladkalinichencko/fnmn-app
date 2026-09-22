"""Turn a verified book Markdown file into a self-contained application bundle."""

import argparse
import json
from pathlib import Path
import re
import shutil


HEADING = re.compile(r'^(#+) (.+)$', re.M)
NUMBER = re.compile(r'^(?:\d+(?:\.\d+)*|∞(?:\.\d+)*|[A-Z]\.\d+(?:\.\d+)*)\s+')
PAGE = re.compile(r'^<!-- PDF page \d+ -->\s*$', re.M)
FOOTNOTE_DEFINITION = re.compile(r'^\[\^[^]]+\]:', re.M)
MATH_ENVIRONMENT = re.compile(r'\\begin\{(aligned|cases|gather|equation\*?)\}(.*?)\\end\{\1\}', re.S)


def math_delimiter_errors(text):
    errors = []
    for match in MATH_ENVIRONMENT.finditer(text):
        formula = match.group(0)
        if _group_depth(formula) != 0 or _delimiter_count(formula, 'left') != _delimiter_count(formula, 'right'):
            line = text[:match.start()].count('\n') + 1
            errors.append(f'math_delimiters:{line}')
    return errors


def _group_depth(formula):
    depth = 0
    index = 0
    while index < len(formula):
        if formula[index] == '\\':
            index += 2 if index + 1 < len(formula) else 1
            continue
        if formula[index] == '{':
            depth += 1
        elif formula[index] == '}':
            depth -= 1
            if depth < 0:
                return depth
        index += 1
    return depth


def _delimiter_count(formula, name):
    return len(re.findall(r'\\' + name + r'(?![a-zA-Z])', formula))


def section_bounds(text, title):
    headings = list(HEADING.finditer(text))
    for index, match in enumerate(headings):
        if match[2].strip() == title:
            level = len(match[1])
            end = next((other.start() for other in headings[index + 1:]
                        if len(other[1]) <= level), len(text))
            return match.start(), end
    raise ValueError(f'heading not found: {title}')


def clean_heading(level, title):
    title = re.sub(r'^\$\\infty(?:\.\d+)*\$\s*(?:\.\d+)*\s*', '', title)
    title = NUMBER.sub('', title).strip()
    return re.sub(r'^[A-Z]\s+', '', title) if level == 1 else title


def join_pages(left, right):
    left, right = left.rstrip(), right.lstrip()
    if not left:
        return right
    if not right:
        return left
    first_line, last_line = right.splitlines()[0], left.splitlines()[-1]
    block_boundary = (first_line.startswith(('#', '$$', '```', '![', '-', '* '))
                      or last_line.startswith(('#', '$$', '```', '![', '-', '* '))
                      or last_line.endswith(('$$', '```')))
    continues = left[-1] not in '.!?;:' or right[0].islower()
    return left + (' ' if continues and not block_boundary else '\n\n') + right


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('config', type=Path)
parser.add_argument('output', type=Path)


def main():
    options = parser.parse_args()

    config = json.loads(options.config.read_text())
    text = options.source.read_text()
    start, _ = section_bounds(text, config['content_start'])
    text = text[start:]
    for title in config.get('drop_sections', []):
        try:
            begin, end = section_bounds(text, title)
        except ValueError:
            continue
        text = text[:begin] + text[end:]

    pages, footnotes = [], []
    for page in PAGE.split(text):
        definition = FOOTNOTE_DEFINITION.search(page)
        if definition:
            footnotes.append(page[definition.start():].strip())
            page = page[:definition.start()]
        pages.append(page.strip())
    text = ''
    for page in pages:
        text = join_pages(text, page)
    if footnotes:
        text += '\n\n' + '\n\n'.join(footnotes)
    if config.get('strip_heading_numbers', True):
        text = HEADING.sub(lambda match: f'{match[1]} {clean_heading(len(match[1]), match[2])}', text)
    text = re.sub(r'!\[Figure from PDF page \d+\]', '![Figure]', text)
    text = re.sub(r'\n{3,}', '\n\n', text).strip() + '\n'

    options.output.mkdir(parents=True, exist_ok=True)
    (options.output / 'content.md').write_text(text)
    assets = options.output / 'assets'
    assets.mkdir(exist_ok=True)
    images = re.findall(r'!\[[^]]*\]\(([^)]+)\)', text)
    for image in images:
        source = options.source.parent / image
        shutil.copy2(source, assets / Path(image).name)

    toc = [{'ordinal': index, 'level': len(match[1]), 'title': match[2].strip()}
           for index, match in enumerate(HEADING.finditer(text), 1)]
    metadata = {key: value for key, value in config.items()
                if key not in {'content_start', 'drop_sections', 'strip_heading_numbers'}}
    metadata.update(schema_version=1, content_file='content.md', assets_directory='assets', toc=toc)
    (options.output / 'metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')

    errors = []
    if '<!-- PDF page ' in text or 'Figure from PDF page ' in text:
        errors.append('page_markers')
    if any(match[2].strip() in config.get('drop_sections', []) for match in HEADING.finditer(text)):
        errors.append('dropped_sections')
    if any(NUMBER.match(match[2]) or re.match(r'^\$\\infty', match[2])
           or (len(match[1]) == 1 and re.match(r'^[A-Z]\s+', match[2]))
           for match in HEADING.finditer(text)):
        errors.append('numbered_headings')
    if any(not (options.output / image).exists() for image in images):
        errors.append('missing_images')
    references = set(re.findall(r'\[\^([^]]+)\](?!:)', text))
    definitions = set(re.findall(r'^\[\^([^]]+)\]:', text, re.M))
    if references != definitions:
        errors.append('footnote_links')
    if '\n\n\n' in text:
        errors.append('excess_blank_lines')
    errors.extend(math_delimiter_errors(text))
    validation = {'headings': len(toc), 'images': len(images), 'errors': errors}
    (options.output / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n')
    if errors:
        raise RuntimeError(f'app export validation failed: {errors}')


if __name__ == '__main__':
    main()
