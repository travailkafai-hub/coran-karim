"""Whisper benchmark (parametric): transcription -> WER + algorithmic mistake detection.
Usage: python bench_whisper.py <model_path_or_id> [tag]
"""
import truststore; truststore.inject_into_ssl()
import os, sys, json, time, torch
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
import soundfile as sf
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from common import load_dataset, wer, diff_has_error, vram_gb, ROOT

MODEL = sys.argv[1] if len(sys.argv)>1 else "tarteel-ai/whisper-base-ar-quran"
tag = sys.argv[2] if len(sys.argv)>2 else os.path.basename(MODEL.replace("\\","/").rstrip("/"))
dev = "cuda" if torch.cuda.is_available() else "cpu"
proc = WhisperProcessor.from_pretrained(MODEL)
model = WhisperForConditionalGeneration.from_pretrained(MODEL, dtype=torch.float16).to(dev).eval()

# Force Arabic transcription via prefix tokens (robust across mono/multilingual finetunes
# whose generation_config is too old to accept the `language=` argument).
_tk = proc.tokenizer
_ar = _tk.convert_tokens_to_ids("<|ar|>")
_tr = _tk.convert_tokens_to_ids("<|transcribe|>")
_nt = _tk.convert_tokens_to_ids("<|notimestamps|>")
if all(isinstance(x,int) and x>=0 for x in (_ar,_tr,_nt)):
    model.generation_config.forced_decoder_ids = [(1,_ar),(2,_tr),(3,_nt)]

def transcribe(feats):
    with torch.no_grad():
        return model.generate(feats, max_new_tokens=200)

ds = load_dataset()
results, wers = [], []
if dev=="cuda": torch.cuda.reset_peak_memory_stats()
for s in ds:
    audio,_ = sf.read(os.path.join(ROOT, s["wav"]))
    feats = proc(audio, sampling_rate=16000, return_tensors="pt").input_features.to(dev).to(model.dtype)
    t0=time.time(); ids=transcribe(feats); dt=time.time()-t0
    hyp = proc.batch_decode(ids, skip_special_tokens=True)[0].strip()
    w = wer(s["ref_uthmani"], hyp); wers.append(w)
    err_corr,_ = diff_has_error(s["ref_uthmani"], hyp)
    err_bad,_  = diff_has_error(s["corrupt_ref"], hyp)
    results.append({"key":s["key"],"hyp":hyp,"wer":round(w,3),
                    "flag_on_correct":err_corr,"flag_on_corrupt":err_bad,"latency_s":round(dt,2)})
    print(f"{s['key']:8s} WER={w:.2f} t={dt:4.1f}s  {hyp[:50]}")

n=len(results)
summary={"model":tag,"piste":"A-transcription","avg_wer":round(sum(wers)/n,3),
         "false_positive_rate":round(sum(r['flag_on_correct'] for r in results)/n,3),
         "detection_recall":round(sum(r['flag_on_corrupt'] for r in results)/n,3),
         "detection_accuracy":round((sum(not r['flag_on_correct'] for r in results)+sum(r['flag_on_corrupt'] for r in results))/(2*n),3),
         "avg_latency_s":round(sum(r['latency_s'] for r in results)/n,2),"vram_gb":vram_gb(),"n":n}
print("\nSUMMARY:",json.dumps(summary,ensure_ascii=False))
json.dump({"summary":summary,"results":results},
          open(os.path.join(ROOT,"data",f"results_{tag}.json"),"w",encoding="utf-8"),
          ensure_ascii=False,indent=2)
