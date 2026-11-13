import json, sys
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from transformers import pipeline
from collections import Counter
data=json.load(open('/tmp/digest-eval/evalset.json'))
pipe=pipeline("zero-shot-classification",model="MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7")
topics=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","software projects","personal diary and everyday life","other"]
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev","other"]
preds=Counter(); personal_wrong=[]
for p in data:
    hyps={f"This post is about {t}":t for t in topics}
    r=pipe(p['text'][:1500],list(hyps),multi_label=True)
    scores=dict(zip([hyps[l] for l in r['labels']],r['scores']))
    pred=max(scores,key=scores.get); pc=canon[topics.index(pred)]
    preds[pc]+=1
    if pc=='personal' and p['gold']!='personal': personal_wrong.append((p['id'],p['gold']))
print('pred dist:',dict(preds))
print('personal preds on non-personal:',len(personal_wrong), personal_wrong[:10])
