"""
Fine-tune Whisper-small on the full Quran dataset.

Starts from openai/whisper-small (244M params, 12 enc + 12 dec layers).
  - batch 8 + grad_accum 4 → effective batch 32
  - LR 1e-5, 2 epochs, encoder UNFROZEN
  - bf16, warmup 500 steps
  - eval every 1000 steps (WER on 100 test clips) for sanity check
  - early stopping if eval_loss does not improve for 3 evaluations

Uses train_combined.jsonl (original 231k + YouTube aligned) if available,
otherwise falls back to train_full.jsonl.

Expected: ~4h on RTX 5080 with combined dataset.
Output: models/whisper-small-ft
"""
import os
os.environ["USE_TF"] = "0"; os.environ["USE_JAX"] = "0"
import truststore; truststore.inject_into_ssl()
import json, time, torch, soundfile as sf, numpy as np
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
from dataclasses import dataclass
from torch.utils.data import Dataset
from transformers import (WhisperProcessor, WhisperForConditionalGeneration,
                          Seq2SeqTrainer, Seq2SeqTrainingArguments,
                          EarlyStoppingCallback)
from jiwer import wer as compute_wer

ROOT        = os.path.dirname(os.path.abspath(__file__))
BASE        = "openai/whisper-small"
OUT         = os.path.join(ROOT, "models", "whisper-small-ft-clean")
_UNIFIED    = os.path.join(ROOT, "data", "manifest_unified.jsonl")
_COMBINED   = os.path.join(ROOT, "data", "train_combined.jsonl")
_ORIG       = os.path.join(ROOT, "data", "train_full.jsonl")
TRAIN_JSONL = _UNIFIED if os.path.exists(_UNIFIED) else (_COMBINED if os.path.exists(_COMBINED) else _ORIG)
TEST_JSONL  = os.path.join(ROOT, "data", "test_voice_full.jsonl")
MAX_LABEL   = 440
N_SANITY    = 3    # clips used for sanity check before training
N_EVAL      = 100  # clips used for mid-training WER evaluation

proc = WhisperProcessor.from_pretrained(BASE, language="arabic", task="transcribe")


# ── Dataset ───────────────────────────────────────────────────────────────────

class DS(Dataset):
    def __init__(self, path):
        rows_raw = [json.loads(l) for l in open(path, encoding="utf-8")]
        self.rows, skipped = [], 0
        for r in rows_raw:
            if len(proc.tokenizer(r["text"]).input_ids) <= MAX_LABEL:
                self.rows.append(r)
            else:
                skipped += 1
        if skipped:
            print(f"  Skipped {skipped} clips > {MAX_LABEL} tokens", flush=True)

    def __len__(self): return len(self.rows)

    def __getitem__(self, i):
        r = self.rows[i]
        audio, _ = sf.read(os.path.join(ROOT, r["wav"]), dtype="float32")
        feats  = proc.feature_extractor(audio, sampling_rate=16000).input_features[0]
        labels = proc.tokenizer(r["text"]).input_ids
        return {"input_features": feats, "labels": labels}


class EvalDS(Dataset):
    """Small dataset for WER evaluation during training (existing wavs only)."""
    def __init__(self, path, n):
        rows = [json.loads(l) for l in open(path, encoding="utf-8")]
        # Keep only clips whose wav exists AND label fits — avoids mid-eval crash
        rows = [r for r in rows
                if os.path.exists(os.path.join(ROOT, r["wav"]))
                and len(proc.tokenizer(r["text"]).input_ids) <= MAX_LABEL]
        rng  = np.random.default_rng(42)
        idx  = rng.choice(len(rows), min(n, len(rows)), replace=False)
        self.rows = [rows[i] for i in idx]

    def __len__(self): return len(self.rows)

    def __getitem__(self, i):
        r = self.rows[i]
        audio, _ = sf.read(os.path.join(ROOT, r["wav"]), dtype="float32")
        feats  = proc.feature_extractor(audio, sampling_rate=16000).input_features[0]
        labels = proc.tokenizer(r["text"]).input_ids
        return {"input_features": feats, "labels": labels, "ref": r["text"]}


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


# ── Sanity check ──────────────────────────────────────────────────────────────

def sanity_check(model, test_rows, label="BASE"):
    """Transcrit N_SANITY clips et affiche le WER — s'exécute avant l'entraînement."""
    model.eval()
    device = next(model.parameters()).device
    refs, hyps = [], []
    with torch.no_grad():
        for r in test_rows[:N_SANITY]:
            wav_path = os.path.join(ROOT, r["wav"])
            if not os.path.exists(wav_path):
                continue
            audio, _ = sf.read(wav_path, dtype="float32")
            feats = proc.feature_extractor(audio, sampling_rate=16000,
                                           return_tensors="pt").input_features.to(device)
            ids = model.generate(feats, language="arabic", task="transcribe",
                                 max_new_tokens=440)
            hyp = proc.tokenizer.decode(ids[0], skip_special_tokens=True).strip()
            refs.append(r["text"])
            hyps.append(hyp)
    wer = compute_wer(refs, hyps) if refs else 1.0
    print(f"[SANITY {label}] WER={wer:.1%} sur {len(refs)} clips", flush=True)
    for ref, hyp in zip(refs[:2], hyps[:2]):
        print(f"  REF: {ref[:80]}", flush=True)
        print(f"  HYP: {hyp[:80]}", flush=True)
    return wer


# ── Compute metrics (for eval during training) ────────────────────────────────

def make_compute_metrics():
    def compute_metrics(pred):
        label_ids = pred.label_ids
        pred_ids  = pred.predictions
        label_ids[label_ids == -100] = proc.tokenizer.pad_token_id
        refs  = proc.tokenizer.batch_decode(label_ids,  skip_special_tokens=True)
        hyps  = proc.tokenizer.batch_decode(pred_ids,   skip_special_tokens=True)
        wer   = compute_wer(refs, hyps)
        return {"wer": round(wer, 4)}
    return compute_metrics


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    cuda_ok = torch.cuda.is_available()
    print(f"CUDA: {cuda_ok}  ({torch.cuda.get_device_name(0) if cuda_ok else 'CPU'})",
          flush=True)

    print(f"Manifest: {TRAIN_JSONL}", flush=True)
    ds = DS(TRAIN_JSONL)
    print(f"Training clips: {len(ds):,}", flush=True)

    eval_ds = None
    if os.path.exists(TEST_JSONL):
        eval_ds = EvalDS(TEST_JSONL, N_EVAL)
        print(f"Eval clips: {len(eval_ds)} (WER toutes les 1000 steps)", flush=True)

    from transformers.trainer_utils import get_last_checkpoint
    last_ckpt = get_last_checkpoint(OUT) if os.path.isdir(OUT) else None

    # Reprise "poids seulement" : l'etat de l'optimiseur d'un ancien checkpoint
    # (sauve avec une version differente de transformers) est incompatible et
    # fait planter le resume complet -> on repart d'un optimiseur neuf mais on
    # garde les poids deja entraines (warm start).
    load_from = last_ckpt if last_ckpt else BASE
    print(f"Poids charges depuis : {load_from}", flush=True)
    model = WhisperForConditionalGeneration.from_pretrained(load_from)
    model.config.forced_decoder_ids = None
    model.config.suppress_tokens    = []
    model.generation_config.forced_decoder_ids = None
    model.config.forced_decoder_ids = proc.get_decoder_prompt_ids(
        language="arabic", task="transcribe")

    # ── Sanity check avec le modèle BASE (avant tout entraînement) ──────────
    if eval_ds and cuda_ok:
        test_rows = [json.loads(l) for l in open(TEST_JSONL, encoding="utf-8")][:N_SANITY]
        model.to("cuda")
        sanity_check(model, test_rows, label="BEFORE_TRAIN")
        model.cpu()

    n_steps_per_epoch = len(ds) // (8 * 4)   # batch=8, grad_accum=4
    eval_steps = min(1000, max(500, n_steps_per_epoch // 4))

    args = Seq2SeqTrainingArguments(
        output_dir=OUT,
        per_device_train_batch_size=4,    # reduit -> libere VRAM (gaming)
        gradient_accumulation_steps=8,    # compense -> effective batch 32 inchange
        learning_rate=1e-5,
        warmup_steps=500,
        num_train_epochs=6,                # 4->6 : dataset unifie ~1.8x plus grand (batch2 inclus)
        bf16=cuda_ok,
        fp16=False,
        logging_steps=200,
        save_strategy="steps" if eval_ds else "epoch",
        save_steps=eval_steps if eval_ds else None,
        save_total_limit=3,
        eval_strategy="steps" if eval_ds else "no",
        eval_steps=eval_steps if eval_ds else None,
        load_best_model_at_end=bool(eval_ds),
        metric_for_best_model="wer" if eval_ds else None,
        greater_is_better=False,
        predict_with_generate=bool(eval_ds),
        generation_max_length=440,
        report_to=[],
        dataloader_num_workers=8,          # I/O : plus de workers (comme Medium)
        dataloader_pin_memory=True,
        ignore_data_skip=True,             # reprise sans re-lire tous les audios
        remove_unused_columns=False,
        use_cpu=not cuda_ok,
    )

    callbacks = []
    if eval_ds:
        # patience 3->8 : le WER est bruite, la loss est le vrai signal -> ne pas couper trop tot
        callbacks.append(EarlyStoppingCallback(early_stopping_patience=8))

    trainer = Seq2SeqTrainer(
        model=model,
        args=args,
        train_dataset=ds,
        eval_dataset=eval_ds,
        data_collator=Collator(proc),
        compute_metrics=make_compute_metrics() if eval_ds else None,
        processing_class=proc.feature_extractor,
        callbacks=callbacks if callbacks else None,
    )
    print(f"\nEntraînement (poids repris, optimiseur neuf) — eval_steps={eval_steps}",
          flush=True)
    t0 = time.time()
    trainer.train(resume_from_checkpoint=None)
    elapsed = time.time() - t0
    print(f"Entraînement termine en {elapsed/3600:.2f}h", flush=True)

    trainer.save_model(OUT)
    proc.save_pretrained(OUT)

    # ── Sanity check après entraînement ─────────────────────────────────────
    if eval_ds and cuda_ok:
        test_rows = [json.loads(l) for l in open(TEST_JSONL, encoding="utf-8")][:N_SANITY]
        sanity_check(model, test_rows, label="AFTER_TRAIN")

    print("WHISPER SMALL FT DONE ->", OUT, flush=True)


if __name__ == "__main__":
    main()
