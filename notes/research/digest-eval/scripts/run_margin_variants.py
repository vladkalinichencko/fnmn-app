"""Margin variants (top1-top2, top1-top3, top1-mean) + length-scaled thresholds on offtopic_eval."""
import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
data=json.load(open('/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/notes/research/digest-eval/data/offtopic_eval.json'))
golds=np.array([p['gold'] for p in data])
texts=[p['text'][:1500] for p in data]
lens=np.array([len(t.split()) for t in texts])
model=SentenceTransformer("Qwen/Qwen3-Embedding-0.6B")
QP="Instruct: Classify the topic of this social media post.\nQuery: "
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects"]
TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
PE=model.encode([QP+t for t in texts],normalize_embeddings=True,batch_size=32)
S=PE@TE.T; srt=np.sort(S,1)
m12=srt[:,-1]-srt[:,-2]; m13=srt[:,-1]-srt[:,-3]; m1m=srt[:,-1]-srt[:,:-1].mean(1)
off=golds=='other'; on=~off
def report(name,score,ths):
    print(f"== {name} ==")
    for t in ths:
        print(f"  th{t}: off-leak {np.mean(score[off]>=t):.0%}  on-filed {np.mean(score[on]>=t):.0%}")
report("margin top1-top2",m12,[0.03,0.05,0.07,0.1])
report("margin top1-top3",m13,[0.03,0.05,0.07,0.1])
report("margin top1-mean(rest)",m1m,[0.05,0.1,0.15,0.2])
def ev(name,score,base,slope,cap):
    th=base+slope*np.minimum(lens,cap); acc=score>=th
    print(f"{name} {base}+{slope}w(cap{cap}): off-leak {np.mean(acc[off]):.0%} on-filed {np.mean(acc[on]):.0%}")
ev("m12-len",m12,0.02,0.0013,60); ev("m12-flat",m12,0.05,0,60); ev("m12-flat",m12,0.07,0,60)
