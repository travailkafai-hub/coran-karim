"""Fine-tune Whisper-base-ar-quran on the FULL Quran x 38 reciters (~235k clips).
Strategy vs Phase 2:
  - Encoder UNFROZEN (enough data to tune full model without overfitting)
  - LR 1e-5 (vs 6e-6), warmup 500 steps
  - 2 epochs, checkpoint every epoch
  - bf16, batch 16
"""
import truststore; truststore.inject_into_ssl()
import os, json, torch, soundfile as sf
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
from dataclasses import dataclass
from torch.utils.data import Dataset
from transformers import (WhisperProcessor, WhisperForConditionalGeneration,
                          Seq2SeqTrainer, Seq2SeqTrainingArguments)

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = "tarteel-ai/whisper-base-ar-quran"
OUT  = os.path.join(ROOT, "models", "whisper-full-ft")
TRAIN_JSONL = os.path.join(ROOT, "data", "train_full.jsonl")
MAX_LABEL_LEN = 440  # Whisper hard limit is 448; leave margin for BOS/EOS tokens

proc = WhisperProcessor.from_pretrained(BASE)

class DS(Dataset):
    def __init__(self, path):
        rows_raw = [json.loads(l) for l in open(path, encoding="utf-8")]
        # Pre-filter rows whose tokenized label exceeds Whisper's 448-token limit
        self.rows = []
        skipped = 0
        for r in rows_raw:
            ids = proc.tokenizer(r["text"]).input_ids
            if len(ids) <= MAX_LABEL_LEN:
                self.rows.append(r)
            else:
                skipped += 1
        if skipped:
            print(f"  Skipped {skipped} clips with labels > {MAX_LABEL_LEN} tokens", flush=True)

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        r = self.rows[i]
        audio, _ = sf.read(os.path.join(ROOT, r["wav"]), dtype="float32")
        feats = proc.feature_extractor(audio, sampling_rate=16000).input_features[0]
        labels = proc.tokenizer(r["text"]).input_ids
        return {"input_features": feats, "labels": labels}

@dataclass
class Collator:
    proc: object
    def __call__(self, batch):
        feats = [{"input_features": b["input_features"]} for b in batch]
        bf = self.proc.feature_extractor.pad(feats, return_tensors="pt")
        labs = [{"input_ids": b["labels"]} for b in batch]
        lb = self.proc.tokenizer.pad(labs, return_tensors="pt")
        labels = lb["input_ids"].masked_fill(lb.attention_mask.ne(1), -100)
        if (labels[:, 0] == self.proc.tokenizer.bos_token_id).all().cpu().item():
            labels = labels[:, 1:]
        bf["labels"] = labels
        return bf

def main():
    if not os.path.exists(TRAIN_JSONL):
        raise FileNotFoundError(f"Run split_full.py first: {TRAIN_JSONL}")

    cuda_ok = torch.cuda.is_available()
    print(f"CUDA available: {cuda_ok}  ({torch.cuda.get_device_name(0) if cuda_ok else 'CPU only'})",
          flush=True)

    ds = DS(TRAIN_JSONL)
    print(f"Training clips after filter: {len(ds)}", flush=True)

    model = WhisperForConditionalGeneration.from_pretrained(BASE)
    model.config.forced_decoder_ids = None
    model.config.suppress_tokens = []
    model.generation_config.forced_decoder_ids = None

    args = Seq2SeqTrainingArguments(
        output_dir=OUT,
        per_device_train_batch_size=16,
        gradient_accumulation_steps=2,     # effective batch 32
        learning_rate=1e-5,
        warmup_steps=500,
        num_train_epochs=2,
        bf16=cuda_ok,                      # bf16 only if GPU available
        fp16=False,
        logging_steps=200,
        save_strategy="epoch",
        save_total_limit=2,
        report_to=[],
        dataloader_num_workers=4,
        remove_unused_columns=False,
        use_cpu=not cuda_ok,
    )

    trainer = Seq2SeqTrainer(
        model=model,
        args=args,
        train_dataset=ds,
        data_collator=Collator(proc),
        processing_class=proc.feature_extractor,
    )
    trainer.train()
    trainer.save_model(OUT)
    proc.save_pretrained(OUT)
    print("WHISPER FULL FT DONE ->", OUT)

if __name__ == "__main__":
    main()
