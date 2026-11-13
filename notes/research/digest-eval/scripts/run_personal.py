import json, sys
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from transformers import pipeline

data=json.load(open('/tmp/digest-eval/evalset.json'))
pipe=pipeline("zero-shot-classification",model="MoritzLaurer/mDeBERTa-v3-base-xnli-multilingual-nli-2mil7")

BASE=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","software projects"]
PERSONAL_VARIANTS={
 "personal blog":"personal blog",
 "личный блог":"личный блог",
 "personal diary":"personal diary and everyday life",
 "записи о жизни":"записи о повседневной жизни и личные истории",
}
canon=["kpop","magazine_covers","graphic_design","film","ai_industry","ml_research","startups","personal","tech_dev","other"]

for pname,ptopic in PERSONAL_VARIANTS.items():
    topics=BASE+[ptopic,"other"]
    correct=0; per={}
    for p in data:
        hyps={f"This post is about {t}":t for t in topics}
        r=pipe(p['text'][:1500],list(hyps),multi_label=True)
        scores=dict(zip([hyps[l] for l in r['labels']],r['scores']))
        pred=max(scores,key=scores.get)
        pred_canon=canon[topics.index(pred)]
        ok=pred_canon==p['gold']; correct+=ok
        c=per.setdefault(p['gold'],[0,0]); c[1]+=1; c[0]+=ok
    print(f"{pname:20} acc={correct}/94={correct/94:.2f} personal={per.get('personal')} other-as-personal-check")
    # how many 'other' posts get personal
    op=sum(1 for p,d in zip(data,[None]*94) if False)
json.dump({},open('/tmp/x','w'))
