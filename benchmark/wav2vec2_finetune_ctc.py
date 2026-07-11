"""
Fine-tune wav2vec2 (CTC) sur le Coran -> forced-aligner frame-level.

But : modele CTC qui sort une probabilite de caractere PAR frame (~20ms),
pour alignement force temps-reel (validation vert/rouge mot-par-mot instantanee
dans l'app, contre le texte canonique connu du verset).

Base : facebook/wav2vec2-xls-r-300m (multilingue, fort sur l'arabe).
  -> alternative legere mobile : facebook/wav2vec2-base (95M) via env W2V_BASE.

Dataset : train_combined.jsonl (244k clips, YouTube inclus). Vocab caractere
avec harakat (data/wav2vec2_vocab.json).

Garde-fous : sanity check, eval WER (CER) periodique, early stopping, reprise auto.
Sortie : models/wav2vec2-quran-ctc
"""
import truststore; truststore.inject_into_ssl()
import os, json, time, torch, soundfile as sf, numpy as np
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
from dataclasses import dataclass
from typing import Dict, List, Union
from torch.utils.data import Dataset
from transformers import (Wav2Vec2CTCTokenizer, Wav2Vec2FeatureExtractor,
                          Wav2Vec2Processor, Wav2Vec2ForCTC,
                          Trainer, TrainingArguments, EarlyStoppingCallback)
from jiwer import wer as compute_wer

ROOT   = os.path.dirname(os.path.abspath(__file__))
BASE   = os.environ.get("W2V_BASE", "facebook/wav2vec2-xls-r-300m")
OUT    = os.path.join(ROOT, "models", "wav2vec2-quran-ctc")
VOCAB  = os.path.join(ROOT, "data", "wav2vec2_vocab.json")
_COMB  = os.path.join(ROOT, "data", "train_combined.jsonl")
_ORIG  = os.path.join(ROOT, "data", "train_full.jsonl")
TRAIN_JSONL = _COMB if os.path.exists(_COMB) else _ORIG
TEST_JSONL  = os.path.join(ROOT, "data", "test_voice_full.jsonl")

SR          = 16000
MAX_AUDIO_S = 20.0     # ignore clips plus longs (memoire wav2vec2)
N_SANITY    = 3
N_EVAL      = 100

# ── Processor (tokenizer caractere + feature extractor) ─────────────────────────
tokenizer = Wav2Vec2CTCTokenizer(VOCAB, unk_token="[UNK]", pad_token="[PAD]",
                                 word_delimiter_token="|")
feat_ext  = Wav2Vec2FeatureExtractor(feature_size=1, sampling_rate=SR,
                                     padding_value=0.0, do_normalize=True,
                                     return_attention_mask=True)
proc = Wav2Vec2Processor(feature_extractor=feat_ext, tokenizer=tokenizer)


class DS(Dataset):
    def __init__(self, path, n=None):
        rows = [json.loads(l) for l in open(path, encoding="utf-8")]
        if n:
            rng = np.random.default_rng(42)
            idx = rng.choice(len(rows), min(n, len(rows)), replace=False)
            rows = [rows[i] for i in idx]
        # garde clips existants et pas trop longs (filtre par taille fichier approx)
        self.rows = rows

    def __len__(self): return len(self.rows)

    def __getitem__(self, i):
        r = self.rows[i]
        audio, _ = sf.read(os.path.join(ROOT, r["wav"]), dtype="float32")
        if len(audio) > MAX_AUDIO_S * SR:
            audio = audio[: int(MAX_AUDIO_S * SR)]
        vals   = proc(audio, sampling_rate=SR).input_values[0]
        labels = proc.tokenizer(r["text"]).input_ids
        return {"input_values": vals, "labels": labels}


@dataclass
class CTCCollator:
    processor: object
    def __call__(self, features):
        inputs = [{"input_values": f["input_values"]} for f in features]
        batch  = self.processor.feature_extractor.pad(inputs, return_tensors="pt")
        labs   = [{"input_ids": f["labels"]} for f in features]
        lb     = self.processor.tokenizer.pad(labs, return_tensors="pt")
        labels = lb["input_ids"].masked_fill(lb.attention_mask.ne(1), -100)
        batch["labels"] = labels
        return batch


def make_compute_metrics():
    def compute_metrics(pred):
        pred_logits = pred.predictions
        pred_ids    = np.argmax(pred_logits, axis=-1)
        labels      = pred.label_ids
        labels[labels == -100] = proc.tokenizer.pad_token_id
        pred_str  = proc.batch_decode(pred_ids)
        label_str = proc.batch_decode(labels, group_tokens=False)
        # CER (caractere) — plus pertinent qu'un WER pour un aligneur
        try:
            cer = compute_wer([" ".join(s) for s in label_str],
                              [" ".join(s) for s in pred_str])
        except Exception:
            cer = 1.0
        return {"cer": round(cer, 4)}
    return compute_metrics


def sanity_check(model, rows, label="BASE"):
    model.eval()
    device = next(model.parameters()).device
    with torch.no_grad():
        for r in rows[:N_SANITY]:
            p = os.path.join(ROOT, r["wav"])
            if not os.path.exists(p): continue
            audio, _ = sf.read(p, dtype="float32")
            iv = proc(audio, sampling_rate=SR, return_tensors="pt").input_values.to(device)
            logits = model(iv).logits
            ids = torch.argmax(logits, dim=-1)
            hyp = proc.batch_decode(ids)[0]
            print(f"[SANITY {label}] REF: {r['text'][:60]}", flush=True)
            print(f"[SANITY {label}] HYP: {hyp[:60]}", flush=True)


def main():
    cuda = torch.cuda.is_available()
    print(f"CUDA: {cuda} ({torch.cuda.get_device_name(0) if cuda else 'CPU'})", flush=True)
    print(f"Base: {BASE}", flush=True)
    print(f"Manifest: {TRAIN_JSONL}", flush=True)

    ds = DS(TRAIN_JSONL)
    print(f"Training clips: {len(ds):,}", flush=True)
    eval_ds = DS(TEST_JSONL, n=N_EVAL) if os.path.exists(TEST_JSONL) else None
    if eval_ds: print(f"Eval clips: {len(eval_ds)}", flush=True)

    model = Wav2Vec2ForCTC.from_pretrained(
        BASE,
        ctc_loss_reduction="mean",
        ctc_zero_infinity=True,   # CLE: ignore les clips ou texte > frames (evite NaN/collapse)
        pad_token_id=proc.tokenizer.pad_token_id,
        vocab_size=len(proc.tokenizer),
        ignore_mismatched_sizes=True,
    )
    model.freeze_feature_encoder()   # standard : on gele l'encodeur CNN bas-niveau

    args = TrainingArguments(
        output_dir=OUT,
        per_device_train_batch_size=4,    # reduit (8->4) pour liberer ~6GB VRAM (gaming)
        gradient_accumulation_steps=8,    # compense (4->8) => effective batch 32 INCHANGE
        learning_rate=1e-4,
        warmup_steps=1000,
        num_train_epochs=2,
        bf16=cuda, fp16=False,
        logging_steps=200,
        save_strategy="steps" if eval_ds else "epoch",
        save_steps=1000 if eval_ds else None,
        save_total_limit=3,
        eval_strategy="steps" if eval_ds else "no",
        eval_steps=1000 if eval_ds else None,
        load_best_model_at_end=bool(eval_ds),
        metric_for_best_model="cer" if eval_ds else None,
        greater_is_better=False,
        report_to=[],
        dataloader_num_workers=6,
        gradient_checkpointing=True,
        use_cpu=not cuda,
    )

    callbacks = [EarlyStoppingCallback(early_stopping_patience=3)] if eval_ds else None

    trainer = Trainer(
        model=model, args=args,
        train_dataset=ds, eval_dataset=eval_ds,
        data_collator=CTCCollator(proc),
        compute_metrics=make_compute_metrics() if eval_ds else None,
        processing_class=proc.feature_extractor,
        callbacks=callbacks,
    )

    if eval_ds and cuda:
        rows = [json.loads(l) for l in open(TEST_JSONL, encoding="utf-8")][:N_SANITY]
        model.to("cuda"); sanity_check(model, rows, "BEFORE_TRAIN")

    from transformers.trainer_utils import get_last_checkpoint
    last = get_last_checkpoint(OUT) if os.path.isdir(OUT) else None
    if last: print(f"Reprise depuis {last}", flush=True)
    t0 = time.time()
    trainer.train(resume_from_checkpoint=last)
    print(f"CTC entraine en {(time.time()-t0)/3600:.2f}h", flush=True)

    trainer.save_model(OUT)
    proc.save_pretrained(OUT)
    if eval_ds and cuda:
        rows = [json.loads(l) for l in open(TEST_JSONL, encoding="utf-8")][:N_SANITY]
        sanity_check(model, rows, "AFTER_TRAIN")
    print("WAV2VEC2 CTC DONE ->", OUT, flush=True)


if __name__ == "__main__":
    main()
