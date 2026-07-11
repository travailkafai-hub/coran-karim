"""Evaluate a (fine-tuned) model on a held-out test split.
Usage:
  python eval_ft.py whisper <model_path> <test.jsonl> [n]
  python eval_ft.py gemma   <base_path>  <test.jsonl> [n] [lora_path]
Reports WER (piste A) + mistake detection (FP, recall, accuracy) on correct/corrupted refs.
"""
import truststore; truststore.inject_into_ssl()
import os, sys, json, time, random, torch
os.environ["HF_HUB_OFFLINE"]="1"
import soundfile as sf
from common import normalize, wer, diff_has_error
ROOT=os.path.dirname(os.path.abspath(__file__))
random.seed(123)

KIND=sys.argv[1]; MODEL=sys.argv[2]; TEST=sys.argv[3]
N=int(sys.argv[4]) if len(sys.argv)>4 else 150
LORA=sys.argv[5] if len(sys.argv)>5 else None

rows=[json.loads(l) for l in open(os.path.join(ROOT,"data",TEST),encoding="utf-8")]
random.shuffle(rows); rows=rows[:N]

def corrupt(text):
    w=text.split()
    if len(w)<2: return text
    m=random.choice(["delete","substitute","swap"]); i=random.randrange(len(w))
    if m=="delete": w.pop(i)
    elif m=="substitute": w[i]="ٱللَّهِ" if w[i]!="ٱللَّهِ" else "رَبِّ"
    else: j=(i+1)%len(w); w[i],w[j]=w[j],w[i]
    return " ".join(w)

def metrics(flags_c, flags_k, wers=None):
    n=len(flags_c)
    out={"n":n,"false_positive_rate":round(sum(flags_c)/n,3),
         "detection_recall":round(sum(flags_k)/n,3),
         "detection_accuracy":round((sum(not x for x in flags_c)+sum(flags_k))/(2*n),3)}
    if wers is not None: out["avg_wer"]=round(sum(wers)/n,3)
    return out

if KIND=="whisper":
    from transformers import WhisperProcessor, WhisperForConditionalGeneration
    proc=WhisperProcessor.from_pretrained(MODEL)
    model=WhisperForConditionalGeneration.from_pretrained(MODEL,dtype=torch.float16).to("cuda").eval()
    tk=proc.tokenizer
    ids=[tk.convert_tokens_to_ids(t) for t in ("<|ar|>","<|transcribe|>","<|notimestamps|>")]
    if all(isinstance(x,int) and x>=0 for x in ids):
        model.generation_config.forced_decoder_ids=[(1,ids[0]),(2,ids[1]),(3,ids[2])]
    fc,fk,wl=[],[],[]; t0=time.time()
    for r in rows:
        a,_=sf.read(os.path.join(ROOT,r["wav"]),dtype="float32")
        feat=proc(a,sampling_rate=16000,return_tensors="pt").input_features.to("cuda").half()
        with torch.no_grad(): out=model.generate(feat,max_new_tokens=200)
        hyp=proc.batch_decode(out,skip_special_tokens=True)[0].strip()
        wl.append(wer(r["text"],hyp))
        fc.append(diff_has_error(r["text"],hyp)[0]); fk.append(diff_has_error(corrupt(r["text"]),hyp)[0])
    s=metrics(fc,fk,wl); s["latency_s"]=round((time.time()-t0)/len(rows),2)
    print("RESULT",json.dumps({"model":MODEL,"test":TEST,**s},ensure_ascii=False))

else:  # gemma
    from transformers import AutoProcessor, AutoModelForMultimodalLM
    proc=AutoProcessor.from_pretrained(MODEL)  # base processor (LoRA-saved one has bad audio defaults)
    model=AutoModelForMultimodalLM.from_pretrained(MODEL,dtype=torch.bfloat16,device_map="cuda").eval()
    if LORA:
        from peft import PeftModel
        model=PeftModel.from_pretrained(model,LORA); model=model.eval()
    TRANSCRIBE=("Transcris fidèlement cet audio de récitation coranique en arabe. Donne UNIQUEMENT le texte arabe transcrit, sans explication.")
    def judge(ref): return (f"Un élève récite le Coran. Le texte EXACT attendu est :\n«{ref}»\n\nÉcoute l'audio et compare-le mot à mot au texte attendu. Réponds STRICTEMENT sur une seule ligne :\n- «VERDICT: CORRECT» si la récitation correspond exactement,\n- «VERDICT: ERREUR - <détail>» s'il y a la moindre différence.")
    def gen(msgs,mx=200):
        enc=proc.apply_chat_template(msgs,tokenize=True,return_dict=True,return_tensors="pt",add_generation_prompt=True).to("cuda")
        il=enc["input_ids"].shape[-1]
        with torch.no_grad(): o=model.generate(**enc,max_new_tokens=mx,do_sample=False,repetition_penalty=1.3)
        return proc.decode(o[0][il:],skip_special_tokens=True).strip()
    def verdict(t):
        T=t.upper()
        if "VERDICT: CORRECT" in T or T.strip().startswith("CORRECT"): return False
        if "ERREUR" in T or "ERROR" in T: return True
        return any(k in T for k in ["MANQUE","CHANG","AJOUT","DIFF","INVERS"])
    wl=[]; fcA,fkA=[],[]; fcB,fkB=[],[]; t0=time.time()
    for r in rows:
        ap=os.path.join(ROOT,r["wav"]); aud={"type":"audio","audio":ap}
        mx=min(220, len(proc.tokenizer(r["text"]).input_ids)+25)  # bound rambling to ~ref length
        hyp=gen([{"role":"user","content":[{"type":"text","text":TRANSCRIBE},aud]}],mx)
        wl.append(wer(r["text"],hyp)); fcA.append(diff_has_error(r["text"],hyp)[0]); fkA.append(diff_has_error(corrupt(r["text"]),hyp)[0])
        rc=gen([{"role":"user","content":[{"type":"text","text":judge(r["text"])},aud]}],80)
        rk=gen([{"role":"user","content":[{"type":"text","text":judge(corrupt(r["text"]))},aud]}],80)
        fcB.append(verdict(rc)); fkB.append(verdict(rk))
    sA=metrics(fcA,fkA,wl); sB=metrics(fcB,fkB)
    lat=round((time.time()-t0)/len(rows),2)
    print("RESULT_A",json.dumps({"model":MODEL,"lora":LORA,"test":TEST,"piste":"A",**sA,"latency_s":lat},ensure_ascii=False))
    print("RESULT_B",json.dumps({"piste":"B",**sB},ensure_ascii=False))
