"""Score digest posts under different zero-shot configs; dump raw scores for offline analysis."""
import json, sys, time
sys.path.insert(0, '/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from transformers import pipeline

TG_TOPICS = ["personal blog","ai news","startups","design thoughts","research"]
X_TOPICS = ["research","deep learning","openai","theo","t3 code","vibecoding","ai development",
            "self improvement","research papers","anthropic","claude","new film","film news",
            "k-pop pictures","magazine covers","design","personal software projects"]
# proposed telegram topics (ru phrases for ru-template test, en for baseline)
TG_TOPICS_PROP_RU = ["новости ИИ и технологий","стартапы и предпринимательство","дизайн и визуальная культура",
                     "исследования и машинное обучение","личные истории и быт"]
TG_TOPICS_PROP_EN = ["ai and tech news","startups and entrepreneurship","design and visual culture",
                     "ml research and papers","personal stories and everyday life"]

MODELS = {
    "md_xnli": "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7",
    "md_mnli": "MoritzLaurer/DeBERTa-v3-base-mnli-fever-anli",
}

def topics_for(network):
    return TG_TOPICS if network == "telegram" else X_TOPICS

posts = [json.loads(l) for l in open('/tmp/digest-sample.jsonl')]
posts = [p for p in posts if p['network'] in ('telegram','x')]
tricky = json.load(open('/tmp/digest-eval/tricky.json'))

results = json.load(open('/tmp/digest-eval/scores.json'))

def score_set(pipe, texts_topics, multi_label, template):
    """texts_topics: list of (key, text, topics). Returns {key: {topic: score}}."""
    out = {}
    for key, text, topics in texts_topics:
        hyps = {template.format(t): t for t in topics}
        try:
            r = pipe(text, list(hyps), multi_label=multi_label)
            scores = r["scores"] if isinstance(r["scores"], list) else [r["scores"]]
            labels = r["labels"]
            out[key] = {hyps[l]: float(s) for l, s in zip(labels, scores)}
        except Exception as e:
            out[key] = {"__error__": str(e)}
    return out

jobs = []
done = set(json.load(open('/tmp/digest-eval/scores.json')).keys()) if __import__('os').path.exists('/tmp/digest-eval/scores.json') else set()
for name, model in MODELS.items():
    if name in done: continue
    jobs.append((name, model, "This post is about {}.", True))
if "md_xnli_argmax" not in done: pass #jobs.append(("md_xnli_argmax", "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7", "This post is about {}.", False))
if "md_xnli_ruhyp" not in done: pass #jobs.append(("md_xnli_ruhyp", "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7", "Этот пост о теме: {}.", True))
if "md_xnli_propru" not in done: pass #jobs.append(("md_xnli_propru", "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7", "Этот пост о теме: {}.", True))
if "md_xnli_propen" not in done: pass #jobs.append(("md_xnli_propen", "MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7", "This post is about {}.", True))

# precompute topic sets per post
def post_topics(p, variant=None):
    if p['network'] == 'telegram':
        if variant == 'propru': return TG_TOPICS_PROP_RU
        if variant == 'propen': return TG_TOPICS_PROP_EN
        return TG_TOPICS
    return X_TOPICS

for name, model, template, ml in jobs:
    t0 = time.time()
    variant = 'propru' if name == 'md_xnli_propru' else ('propen' if name == 'md_xnli_propen' else None)
    # for proposed-topic jobs only score telegram posts; baseline jobs score all
    subset = posts if variant is None else [p for p in posts if p['network'] == 'telegram']
    data = [(p['id'], (p['text'] or '')[:1500], post_topics(p, variant)) for p in subset]
    # tricky texts: telegram topics (ru) — use TG set for all since most are ru; en ones too
    for t in tricky:
        tt = TG_TOPICS_PROP_RU if variant == 'propru' else (TG_TOPICS_PROP_EN if variant == 'propen' else TG_TOPICS)
        data.append((t['id'], t['text'], tt))
    print(f"loading {name} ({model}) ...", flush=True)
    pipe = pipeline("zero-shot-classification", model=model)
    res = score_set(pipe, data, ml, template)
    results[name] = res
    print(f"  {name}: {len(res)} texts in {time.time()-t0:.0f}s", flush=True)
    json.dump(results, open('/tmp/digest-eval/scores.json','w'), ensure_ascii=False)

print("saved /tmp/digest-eval/scores.json")
