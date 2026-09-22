"""Math defects a mechanical cleaner must not repair."""

import re


MATH_REGION = re.compile(
    r'\$\$.*?\$\$|\\\[.*?\\\]|\\\(.*?\\\)|(?<!\$)\$(?!\$).*?(?<!\$)\$(?!\$)'
    r'|\\begin\{(aligned|cases|gather|equation\*?)\}.*?\\end\{\1\}',
    re.S)
GROUNDING = re.compile(r'<\|ref\|>.*?<\|/ref\|><\|det\|>.*?<\|/det\|>\s*', re.S)
FORMULA_TYPES = {'unbalanced_group', 'unbalanced_left_right'}


def group_depth(formula):
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


def delimiter_count(formula, name):
    return len(re.findall(r'\\' + name + r'(?![a-zA-Z])', formula))


def math_issues(text):
    issues = []
    for match in MATH_REGION.finditer(text):
        formula = match.group(0)
        line = text[:match.start()].count('\n') + 1
        depth = group_depth(formula)
        left = delimiter_count(formula, 'left')
        right = delimiter_count(formula, 'right')
        if depth != 0:
            issues.append({'type': 'unbalanced_group', 'depth': depth, 'line': line, 'formula': formula})
        if left != right:
            issues.append({
                'type': 'unbalanced_left_right', 'left': left, 'right': right, 'line': line, 'formula': formula,
            })
    return issues


def select_formula(text):
    matches = list(GROUNDING.finditer(text))
    if matches:
        text = '\n\n'.join(
            text[match.end():matches[i + 1].start() if i + 1 < len(matches) else len(text)].strip()
            for i, match in enumerate(matches))
    regions = [match.group(0) for match in MATH_REGION.finditer(text)]
    if len(regions) != 1 or math_issues(regions[0]):
        return None
    return regions[0]


def formula_jobs(candidates):
    jobs = []
    seen = set()
    for page in candidates:
        for issue in page.get('issues', []):
            if issue.get('type') not in FORMULA_TYPES or 'image' not in issue or 'equation' not in issue:
                continue
            key = (page['page'], issue['equation'])
            if key in seen:
                continue
            seen.add(key)
            jobs.append((page['page'], issue))
    return jobs
