import json, sys, time
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from transformers import pipeline
import numpy as np

TOPIC_SETS = {
 "EN_SHORT": ["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects","other"],
 "RU": ["k-pop и айдолы","обложки журналов","графический дизайн","фильмы и кино","искусственный интеллект","исследования машинного обучения","стартапы","личные истории","софтовые проекты","другое"],
 "DESCR": ["photos and news about k-pop idols","photos of magazine covers","branding, identity and visual design","movies, series and the film industry","AI companies, models and products","ML research papers and methods","startup ideas and entrepreneurship","personal diary and everyday life","software projects and dev tools","none of these"],
 "OLD_TG": ["personal blog","ai news","startups","design thoughts","research","other"],
}
GOLDMAP = {"kpop":"k-pop pictures","magazine_covers":"magazine covers","graphic_design":"graphic design","film":"film and cinema","ai_industry":"artificial intelligence","ml_research":"machine learning research","startups":"startups and business","personal":"personal stories","tech_dev":"software projects","other":"other"}

data = json.load(open('/tmp/digest-eval/evalset.json'))

def is_ru(t):
    return sum(1 for c in t if 'а'<=c.lower()<='я' or c=='ё')>sum(1 for c in t if 'a'<=c.lower()<='z')

# --- NLI argmax per topic set ---
pipe = pipeline("zero-shot-classification", model="MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7")
nli = {}
for name, topics in TOPIC_SETS.items():
    t0=time.time(); correct=0; details=[]
    for p in data:
        hyps={f"This post is about {t}":t for t in topics}
        r=pipe(p['text'][:1500], list(hyps), multi_label=True)
        scores=dict(zip([hyps[l] for l in r['labels']], r['scores']))
        pred=max(scores,key=scores.get)
        # map predicted topic name back to canonical via position in set
        gold_canon = p['gold']
        # gold is canonical; predicted is topic string of this set -> map set index to canonical
        canon_order=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev","other"]
        pred_canon = canon_order[topics.index(pred)] if pred in topics else "other"
        ok = pred_canon==gold_canon
        correct+=ok
        details.append({'id':p['id'],'gold':gold_canon,'pred':pred_canon,'pred_topic':pred,'score':round(scores[pred],3),'ok':ok})
    nli[name]={'acc':correct/len(data),'details':details}
    print(f"NLI {name}: acc={correct}/{len(data)} = {correct/len(data):.2f}  ({time.time()-t0:.0f}s)",flush=True)
    json.dump(nli,open('/tmp/digest-eval/nli_results.json','w'),ensure_ascii=False)

# --- embeddings ---
from sentence_transformers import SentenceTransformer
model = SentenceTransformer("intfloat/multilingual-e5-base")
for name, topics in TOPIC_SETS.items():
    t0=time.time()
    topic_emb = model.encode(["passage: "+t for t in topics], normalize_embeddings=True)
    texts = [p['text'][:1500] for p in data]
    post_emb = model.encode(["query: "+t for t in texts], normalize_embeddings=True)
    sims = post_emb @ topic_emb.T
    canon_order=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev","other"]
    correct=0; details=[]
    for i,p in enumerate(data):
        j=int(np.argmax(sims[i])); pred_canon=canon_order[j]
        ok=pred_canon==p['gold']; correct+=ok
        details.append({'id':p['id'],'gold':p['gold'],'pred':pred_canon,'score':round(float(sims[i][j]),3),'ok':ok})
    nli['EMB_'+name]={'acc':correct/len(data),'details':details}
    print(f"EMB {name}: acc={correct}/{len(data)} = {correct/len(data):.2f}  ({time.time()-t0:.0f}s)",flush=True)
    json.dump(nli,open('/tmp/digest-eval/nli_results.json','w'),ensure_ascii=False)

# confusion for best config
print("\n--- per-class acc, best ---")
for name in ['EMB_DESCR','NLI_DESCR']:
    d=nli[name]['details']
    from collections import defaultdict
    cls=defaultdict(lambda:[0,0])
    for x in d: cls[x['gold']][1]+=1; cls[x['gold']][0]+=x['ok']
    print(name, {k:f"{a}/{b}" for k,(a,b) in cls.items()})
