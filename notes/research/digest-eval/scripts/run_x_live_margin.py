"""Margin distribution + pseudo-label Mahalanobis probe on 400 live X posts from the store."""
import json, sys, numpy as np
sys.path.insert(0,'/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server')
from sentence_transformers import SentenceTransformer
raw=[json.loads(l) for l in open('/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/server/digest/out/posts.jsonl')]
xs=[p for p in raw if p.get('network')=='x' and (p.get('text') or '').strip()]
xs.sort(key=lambda p:p.get('posted_at',''),reverse=True); xs=xs[:400]
TOPICS=["film updates","software development","web design","research","artificial intelligence","deep learning"]
model=SentenceTransformer("Qwen/Qwen3-Embedding-0.6B")
QP="Instruct: Classify the topic of this social media post.\nQuery: "
TE=model.encode(["passage: "+t for t in TOPICS],normalize_embeddings=True)
PE=model.encode([QP+(p['text'] or '')[:1500] for p in xs],normalize_embeddings=True,batch_size=32)
S=PE@TE.T; srt=np.sort(S,1)
m12=srt[:,-1]-srt[:,-2]; pred=S.argmax(1)
for t in [0.03,0.05,0.07,0.1]:
    print(f"m12>={t}: filed {np.mean(m12>=t):.0%}")
strong=m12>=0.12
classes=sorted(set(pred[strong]))
print("pseudo-labeled:",int(strong.sum()),"classes:",{TOPICS[c]:int((pred[strong]==c).sum()) for c in classes})
