"""Feasibility probe: one LoRA training step on Gemma 4 E2B with audio input."""
import truststore; truststore.inject_into_ssl()
import os, torch
os.environ["HF_HUB_OFFLINE"]="1"
from transformers import AutoProcessor, AutoModelForMultimodalLM
from peft import LoraConfig, get_peft_model
ROOT=os.path.dirname(os.path.abspath(__file__))
M=os.path.join(ROOT,"models","gemma-4-E2B-it")
AUDIO=os.path.join(ROOT,"data","audio","112001.wav")  # qul huwa Allahu ahad
TARGET="قُلْ هُوَ ٱللَّهُ أَحَدٌ"

proc=AutoProcessor.from_pretrained(M)
model=AutoModelForMultimodalLM.from_pretrained(M,dtype=torch.bfloat16,device_map="cuda")
model.gradient_checkpointing_enable(); model.config.use_cache=False

lora=LoraConfig(r=16, lora_alpha=32, lora_dropout=0.05,
    target_modules=r".*(q_proj|k_proj|v_proj|o_proj|gate_proj|up_proj|down_proj)\.linear$",
    task_type="CAUSAL_LM")
model=get_peft_model(model,lora)
model.print_trainable_parameters()

instr="Transcris fidèlement cet audio de récitation coranique en arabe. Donne UNIQUEMENT le texte arabe."
user=[{"type":"text","text":instr},{"type":"audio","audio":AUDIO}]
full=[{"role":"user","content":user},{"role":"assistant","content":[{"type":"text","text":TARGET}]}]
prompt=[{"role":"user","content":user}]

enc=proc.apply_chat_template(full,tokenize=True,return_dict=True,return_tensors="pt",add_generation_prompt=False)
pl=proc.apply_chat_template(prompt,tokenize=True,return_dict=True,return_tensors="pt",add_generation_prompt=True)["input_ids"].shape[-1]
enc={k:(v.to("cuda") if hasattr(v,"to") else v) for k,v in enc.items()}
labels=enc["input_ids"].clone(); labels[:,:pl]=-100
enc["labels"]=labels

torch.cuda.reset_peak_memory_stats()
out=model(**enc); loss=out.loss
loss.backward()
print("LOSS:",float(loss))
print("prompt_len:",pl,"total_len:",enc["input_ids"].shape[-1])
print("PEAK VRAM GB:",round(torch.cuda.max_memory_allocated()/1e9,2))
print("PROBE OK")
