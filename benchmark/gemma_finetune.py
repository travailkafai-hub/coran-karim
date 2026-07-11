"""LoRA fine-tuning of Gemma 4 E2B on audio SFT (ASR + direct judgment). Custom loop, batch=1 + grad accum."""
import truststore; truststore.inject_into_ssl()
import os, sys, json, math, time, random, torch
os.environ["HF_HUB_OFFLINE"]="1"
from transformers import AutoProcessor, AutoModelForMultimodalLM, get_cosine_schedule_with_warmup
from peft import LoraConfig, get_peft_model
ROOT=os.path.dirname(os.path.abspath(__file__))
M=os.path.join(ROOT,"models","gemma-4-E2B-it")
OUT=os.path.join(ROOT,"models","gemma-4-E2B-lora")
MAX_SAMPLES=int(sys.argv[1]) if len(sys.argv)>1 else 10000
EPOCHS=1; ACCUM=16; LR=2e-4; LOG=50

proc=AutoProcessor.from_pretrained(M)
model=AutoModelForMultimodalLM.from_pretrained(M,dtype=torch.bfloat16,device_map="cuda")
model.config.use_cache=False
model.gradient_checkpointing_enable(); model.enable_input_require_grads()
lora=LoraConfig(r=16,lora_alpha=32,lora_dropout=0.05,
    target_modules=r".*(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)\.linear$",
    task_type="CAUSAL_LM")
model=get_peft_model(model,lora); model.print_trainable_parameters()

rows=[json.loads(l) for l in open(os.path.join(ROOT,"data","gemma_sft.jsonl"),encoding="utf-8")]
random.seed(0); random.shuffle(rows); rows=rows[:MAX_SAMPLES]
print(f"Training on {len(rows)} examples, {EPOCHS} epoch(s)",flush=True)

def build(ex):
    user=[{"type":"text","text":ex["user"]},{"type":"audio","audio":os.path.join(ROOT,ex["audio"])}]
    full=[{"role":"user","content":user},{"role":"assistant","content":[{"type":"text","text":ex["target"]}]}]
    enc=proc.apply_chat_template(full,tokenize=True,return_dict=True,return_tensors="pt",add_generation_prompt=False)
    pl=proc.apply_chat_template([{"role":"user","content":user}],tokenize=True,return_dict=True,
                                return_tensors="pt",add_generation_prompt=True)["input_ids"].shape[-1]
    enc={k:(v.to("cuda") if hasattr(v,"to") else v) for k,v in enc.items()}
    lab=enc["input_ids"].clone(); lab[:,:pl]=-100; enc["labels"]=lab
    return enc

opt=torch.optim.AdamW([p for p in model.parameters() if p.requires_grad],lr=LR)
total=math.ceil(len(rows)/ACCUM)*EPOCHS
sched=get_cosine_schedule_with_warmup(opt,int(0.03*total),total)
model.train(); step=0; run=0.0; t0=time.time()
for ep in range(EPOCHS):
    for i,ex in enumerate(rows):
        try:
            enc=build(ex); loss=model(**enc).loss/ACCUM; loss.backward(); run+=loss.item()*ACCUM
        except torch.cuda.OutOfMemoryError:
            torch.cuda.empty_cache(); continue
        if (i+1)%ACCUM==0:
            torch.nn.utils.clip_grad_norm_([p for p in model.parameters() if p.requires_grad],1.0)
            opt.step(); sched.step(); opt.zero_grad(); step+=1
            if step%LOG==0:
                el=time.time()-t0; print(f"step {step}/{total} loss={run/(LOG*ACCUM):.3f} lr={sched.get_last_lr()[0]:.2e} {el/60:.1f}min vram={torch.cuda.max_memory_allocated()/1e9:.1f}GB",flush=True); run=0.0
model.save_pretrained(OUT); proc.save_pretrained(OUT)
print("GEMMA LORA DONE ->",OUT,flush=True)
