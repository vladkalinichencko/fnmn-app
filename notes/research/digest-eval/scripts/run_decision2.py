import json
from transformers import AutoModel
model = AutoModel.from_pretrained("vllm-sr/Decision-2.0-Eos-0.8B", trust_remote_code=True)
data=json.load(open('/Users/vladislavkalinichenko/VSCodeProjects/FNMN App/notes/research/digest-eval/data/offtopic_eval.json'))
TOPICS=["k-pop pictures","magazine covers","graphic design","film and cinema","artificial intelligence","machine learning research","startups and business","personal stories","software projects","none of these topics"]
out=[]
for i,p in enumerate(data):
    r=model.system_one(state=p['text'][:1500], questions={"topic":{"type":"choice","instructions":"Which topic does this social media post belong to? Answer none of these topics if it fits no listed topic.","criteria":{t:t for t in TOPICS}}})
    a=r["answers"]["topic"]
    out.append({"gold":p['gold'],"choice":a.get("choice"),"confidence":a.get("confidence"),"probs":a.get("probabilities",{})})
    if i%20==0: print(i, flush=True)
json.dump(out,open('/tmp/decision_eval.json','w'))
print("DONE", len(out))
