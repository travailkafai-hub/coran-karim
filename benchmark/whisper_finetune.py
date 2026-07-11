"""Continued fine-tuning of Whisper-base-ar-quran on the 3-Hizb x 13-reciter dataset."""
import truststore; truststore.inject_into_ssl()
import os, json, torch, soundfile as sf
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
from dataclasses import dataclass
from torch.utils.data import Dataset
from transformers import (WhisperProcessor, WhisperForConditionalGeneration,
                          Seq2SeqTrainer, Seq2SeqTrainingArguments)
ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = "tarteel-ai/whisper-base-ar-quran"
OUT  = os.path.join(ROOT, "models", "whisper-base-ft")

proc = WhisperProcessor.from_pretrained(BASE)

class DS(Dataset):
    def __init__(self, path):
        self.rows=[json.loads(l) for l in open(path,encoding="utf-8")]
    def __len__(self): return len(self.rows)
    def __getitem__(self,i):
        r=self.rows[i]
        audio,_=sf.read(os.path.join(ROOT,r["wav"]),dtype="float32")
        feats=proc.feature_extractor(audio,sampling_rate=16000).input_features[0]
        labels=proc.tokenizer(r["text"]).input_ids
        return {"input_features":feats,"labels":labels}

@dataclass
class Collator:
    proc: object
    def __call__(self, batch):
        feats=[{"input_features":b["input_features"]} for b in batch]
        bf=self.proc.feature_extractor.pad(feats,return_tensors="pt")
        labs=[{"input_ids":b["labels"]} for b in batch]
        lb=self.proc.tokenizer.pad(labs,return_tensors="pt")
        labels=lb["input_ids"].masked_fill(lb.attention_mask.ne(1),-100)
        if (labels[:,0]==self.proc.tokenizer.bos_token_id).all().cpu().item():
            labels=labels[:,1:]
        bf["labels"]=labels
        return bf

def main():
    model = WhisperForConditionalGeneration.from_pretrained(BASE)
    model.config.forced_decoder_ids = None
    model.config.suppress_tokens = []
    model.generation_config.forced_decoder_ids = None
    model.freeze_encoder()  # preserve acoustic robustness, adapt decoder only -> less overfit
    args=Seq2SeqTrainingArguments(
        output_dir=OUT, per_device_train_batch_size=16, gradient_accumulation_steps=1,
        learning_rate=6e-6, warmup_steps=150, num_train_epochs=1,
        bf16=True, logging_steps=50, save_strategy="epoch", save_total_limit=1,
        report_to=[], dataloader_num_workers=4, remove_unused_columns=False)
    trainer=Seq2SeqTrainer(model=model, args=args,
        train_dataset=DS(os.path.join(ROOT,"data","train.jsonl")),
        data_collator=Collator(proc), processing_class=proc.feature_extractor)
    trainer.train()
    trainer.save_model(OUT); proc.save_pretrained(OUT)
    print("WHISPER FT DONE ->", OUT)

if __name__=="__main__":
    main()
