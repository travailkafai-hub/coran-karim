"""Gemma 4 audio benchmark — both pistes:
  Piste A: audio -> transcription -> WER + algorithmic mistake detection
  Piste B: audio + reference text -> direct error judgment (no transcription step)
Usage: python bench_gemma.py google/gemma-4-E2B-it
"""
import truststore; truststore.inject_into_ssl()
import os, sys, json, time, torch
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
from transformers import AutoProcessor, AutoModelForMultimodalLM
from common import load_dataset, wer, diff_has_error, vram_gb, ROOT

MODEL = sys.argv[1] if len(sys.argv)>1 else "google/gemma-4-E2B-it"
tag = os.path.basename(MODEL.replace("\\","/").rstrip("/"))
proc = AutoProcessor.from_pretrained(MODEL)
model = AutoModelForMultimodalLM.from_pretrained(MODEL, dtype="auto", device_map="auto").eval()

def run(messages, max_new=220):
    inputs = proc.apply_chat_template(messages, tokenize=True, return_dict=True,
                                      return_tensors="pt", add_generation_prompt=True).to(model.device)
    ilen = inputs["input_ids"].shape[-1]
    t0=time.time()
    with torch.no_grad():
        out = model.generate(**inputs, max_new_tokens=max_new, do_sample=False)
    dt=time.time()-t0
    return proc.decode(out[0][ilen:], skip_special_tokens=True).strip(), dt

TRANSCRIBE = ("Transcris fidèlement cet audio de récitation coranique en arabe. "
              "Donne UNIQUEMENT le texte arabe transcrit, sans aucune explication, sans saut de ligne.")

def judge_prompt(ref):
    return (f"Un élève récite le Coran. Le texte EXACT attendu est :\n«{ref}»\n\n"
            "Écoute l'audio et compare-le mot à mot au texte attendu. "
            "Réponds STRICTEMENT sur une seule ligne :\n"
            "- «VERDICT: CORRECT» si la récitation correspond exactement au texte attendu,\n"
            "- «VERDICT: ERREUR - <détail>» s'il y a la moindre différence (mot manquant, ajouté ou changé).")

def parse_verdict(txt):
    t=txt.upper()
    if "VERDICT: CORRECT" in t or t.strip().startswith("CORRECT"):
        return False
    if "ERREUR" in t or "ERROR" in t or "VERDICT: ERREUR" in t:
        return True
    # fallback heuristic
    return any(k in t for k in ["MANQUE","DIFFÉR","DIFFER","CHANG","AJOUT","SUBSTIT"])

ds = load_dataset()
if torch.cuda.is_available(): torch.cuda.reset_peak_memory_stats()
resA, resB, wers = [], [], []
for s in ds:
    apath = os.path.join(ROOT, s["wav"]).replace("\\","/")
    audio_part = {"type":"audio","audio":apath}
    # --- Piste A: transcription ---
    msgs=[{"role":"user","content":[{"type":"text","text":TRANSCRIBE}, audio_part]}]
    hyp,dtA = run(msgs, 220)
    w=wer(s["ref_uthmani"],hyp); wers.append(w)
    eC,_=diff_has_error(s["ref_uthmani"],hyp); eB,_=diff_has_error(s["corrupt_ref"],hyp)
    resA.append({"key":s["key"],"hyp":hyp,"wer":round(w,3),
                 "flag_on_correct":eC,"flag_on_corrupt":eB,"latency_s":round(dtA,2)})
    # --- Piste B: direct judgment (correct ref then corrupt ref) ---
    rc,dtB1 = run([{"role":"user","content":[{"type":"text","text":judge_prompt(s["ref_uthmani"])}, audio_part]}],120)
    rk,dtB2 = run([{"role":"user","content":[{"type":"text","text":judge_prompt(s["corrupt_ref"])}, audio_part]}],120)
    vC=parse_verdict(rc); vK=parse_verdict(rk)
    resB.append({"key":s["key"],"verdict_on_correct":vC,"verdict_on_corrupt":vK,
                 "raw_correct":rc[:120],"raw_corrupt":rk[:120],"latency_s":round(dtB1+dtB2,2)})
    print(f"{s['key']:8s} A:WER={w:.2f} | B:corr={'ERR' if vC else 'OK '} corrupt={'ERR' if vK else 'OK '} | {hyp[:40]}")

n=len(ds)
sumA={"model":MODEL,"piste":"A-transcription","avg_wer":round(sum(wers)/n,3),
      "false_positive_rate":round(sum(r['flag_on_correct'] for r in resA)/n,3),
      "detection_recall":round(sum(r['flag_on_corrupt'] for r in resA)/n,3),
      "detection_accuracy":round((sum(not r['flag_on_correct'] for r in resA)+sum(r['flag_on_corrupt'] for r in resA))/(2*n),3),
      "avg_latency_s":round(sum(r['latency_s'] for r in resA)/n,2)}
sumB={"model":MODEL,"piste":"B-jugement-direct",
      "false_positive_rate":round(sum(r['verdict_on_correct'] for r in resB)/n,3),
      "detection_recall":round(sum(r['verdict_on_corrupt'] for r in resB)/n,3),
      "detection_accuracy":round((sum(not r['verdict_on_correct'] for r in resB)+sum(r['verdict_on_corrupt'] for r in resB))/(2*n),3),
      "avg_latency_s":round(sum(r['latency_s'] for r in resB)/n/2,2)}
out={"vram_gb":vram_gb(),"n":n,"summary_A":sumA,"summary_B":sumB,"resultsA":resA,"resultsB":resB}
print("\nSUMMARY A:",json.dumps(sumA,ensure_ascii=False))
print("SUMMARY B:",json.dumps(sumB,ensure_ascii=False))
json.dump(out, open(os.path.join(ROOT,"data",f"results_{tag}.json"),"w",encoding="utf-8"),
          ensure_ascii=False,indent=2)
