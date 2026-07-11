"""Phase 4 — Whisper fine-tune WITH noise augmentation.

Starts from Phase 3 checkpoint (models/whisper-full-ft) and continues
training with on-the-fly noise augmentation (prob=0.4, SNR 5–20 dB).
Also merges YouTube clips (manifest_youtube.jsonl) when available.

Changes vs Phase 3:
  - noise_augment.random_augment() applied in DS.__getitem__
  - LR halved to 5e-6 (fine adjustments, not full re-training)
  - 1 epoch (noise robustness needs fewer steps than domain adaptation)
"""
import truststore; truststore.inject_into_ssl()
import os, json, torch, soundfile as sf
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
from dataclasses import dataclass
from torch.utils.data import Dataset
from transformers import (WhisperProcessor, WhisperForConditionalGeneration,
                          Seq2SeqTrainer, Seq2SeqTrainingArguments)
from noise_augment import random_augment

ROOT       = os.path.dirname(os.path.abspath(__file__))
BASE       = os.path.join(ROOT, "models", "whisper-full-ft")   # Phase 3 checkpoint
OUT        = os.path.join(ROOT, "models", "whisper-phase4-noisy")
TRAIN_JSONL = os.path.join(ROOT, "data", "train_full.jsonl")
YT_JSONL    = os.path.join(ROOT, "data", "manifest_youtube.jsonl")  # optional
MAX_LABEL_LEN = 440

proc = WhisperProcessor.from_pretrained(BASE)


def load_rows(path, wav_key="wav"):
    if not os.path.exists(path):
        return []
    out = []
    for l in open(path, encoding="utf-8"):
        r = json.loads(l)
        ids = proc.tokenizer(r["text"]).input_ids
        if len(ids) <= MAX_LABEL_LEN:
            out.append((r[wav_key], r["text"]))
    return out


class DS(Dataset):
    def __init__(self, rows: list[tuple[str, str]], augment: bool = True):
        self.rows = rows
        self.augment = augment

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        wav_path, text = self.rows[i]
        audio, _ = sf.read(os.path.join(ROOT, wav_path), dtype="float32")
        if self.augment:
            audio = random_augment(audio, sr=16000, prob=0.4, snr_range_db=(5.0, 20.0))
        feats = proc.feature_extractor(audio, sampling_rate=16000).input_features[0]
        labels = proc.tokenizer(text).input_ids
        return {"input_features": feats, "labels": labels}


@dataclass
class Collator:
    proc: object
    def __call__(self, batch):
        feats = [{"input_features": b["input_features"]} for b in batch]
        bf    = self.proc.feature_extractor.pad(feats, return_tensors="pt")
        labs  = [{"input_ids": b["labels"]} for b in batch]
        lb    = self.proc.tokenizer.pad(labs, return_tensors="pt")
        labels = lb["input_ids"].masked_fill(lb.attention_mask.ne(1), -100)
        if (labels[:, 0] == self.proc.tokenizer.bos_token_id).all().cpu().item():
            labels = labels[:, 1:]
        bf["labels"] = labels
        return bf


def main():
    if not os.path.exists(BASE):
        raise FileNotFoundError(f"Phase 3 model not found: {BASE}. Run whisper_finetune_full.py first.")

    cuda_ok = torch.cuda.is_available()
    print(f"CUDA: {cuda_ok}  ({torch.cuda.get_device_name(0) if cuda_ok else 'CPU only'})", flush=True)

    rows = load_rows(TRAIN_JSONL, wav_key="wav")
    print(f"Clips from Phase 3 dataset: {len(rows)}", flush=True)

    # Add YouTube clips if available and aligned (have a "wav" key + "text")
    yt_rows = load_rows(YT_JSONL, wav_key="wav")
    if yt_rows:
        rows.extend(yt_rows)
        print(f"  + {len(yt_rows)} YouTube clips → total {len(rows)}", flush=True)

    ds = DS(rows, augment=True)

    model = WhisperForConditionalGeneration.from_pretrained(BASE)
    model.config.forced_decoder_ids = None
    model.config.suppress_tokens = []
    model.generation_config.forced_decoder_ids = None

    args = Seq2SeqTrainingArguments(
        output_dir=OUT,
        per_device_train_batch_size=16,
        gradient_accumulation_steps=2,
        learning_rate=5e-6,       # halved vs Phase 3
        warmup_steps=200,
        num_train_epochs=1,
        bf16=cuda_ok,
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
    print("WHISPER PHASE 4 DONE ->", OUT, flush=True)


if __name__ == "__main__":
    main()
