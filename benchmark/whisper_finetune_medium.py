"""
Fine-tune Whisper-medium on the full Quran dataset.

Whisper Medium = 769M params, 24 enc + 24 dec layers.
  - batch 4 + grad_accum 8 → effective batch 32
  - gradient_checkpointing=True (obligatoire, 16 GB VRAM)
  - LR 8e-6, 2 epochs
  - eval every 1000 steps, early stopping patience=3

Uses train_combined.jsonl if available, else train_full.jsonl.
Output: models/whisper-medium-ft
"""
import truststore; truststore.inject_into_ssl()
import os, json, time, torch, soundfile as sf, numpy as np
os.environ.setdefault("HF_HOME", os.path.join(os.path.dirname(__file__), ".hf"))
from dataclasses import dataclass
from torch.utils.data import Dataset
from transformers import (WhisperProcessor, WhisperForConditionalGeneration,
                          Seq2SeqTrainer, Seq2SeqTrainingArguments,
                          EarlyStoppingCallback)
from jiwer import wer as compute_wer

ROOT        = os.path.dirname(os.path.abspath(__file__))
BASE        = "openai/whisper-medium"
OUT         = os.path.join(ROOT, "models", "whisper-medium-ft")
_COMBINED   = os.path.join(ROOT, "data", "train_combined.jsonl")
_ORIG       = os.path.join(ROOT, "data", "train_full.jsonl")
TRAIN_JSONL = _COMBINED if os.path.exists(_COMBINED) else _ORIG
TEST_JSONL  = os.path.join(ROOT, "data", "test_voice_full.jsonl")
MAX_LABEL   = 440
N_SANITY    = 3
N_EVAL      = 100

proc = WhisperProcessor.from_pretrained(BASE, language="arabic", task="transcribe")


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
    def __init__(self, path, n):
        rows = [json.loads(l) for l in open(path, encoding="utf-8")]
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


def sanity_check(model, test_rows, label="BASE"):
    model.eval()
    device = next(model.parameters()).device
    refs, hyps = [], []
    with torch.no_grad():
        for r in test_rows[:N_SANITY]:
            wav_path = os.path.join(ROOT, r["wav"])
            if not os.path.exists(wav_path): continue
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


def make_compute_metrics():
    def compute_metrics(pred):
        label_ids = pred.label_ids
        pred_ids  = pred.predictions
        label_ids[label_ids == -100] = proc.tokenizer.pad_token_id
        refs  = proc.tokenizer.batch_decode(label_ids,  skip_special_tokens=True)
        hyps  = proc.tokenizer.batch_decode(pred_ids,   skip_special_tokens=True)
        return {"wer": round(compute_wer(refs, hyps), 4)}
    return compute_metrics


def main():
    cuda_ok = torch.cuda.is_available()
    print(f"CUDA: {cuda_ok}  ({torch.cuda.get_device_name(0) if cuda_ok else 'CPU'})",
          flush=True)

    if cuda_ok:
        vram_gb = torch.cuda.get_device_properties(0).total_memory / 1e9
        print(f"VRAM: {vram_gb:.1f} GB", flush=True)
        if vram_gb < 14:
            print("  AVERTISSEMENT: Medium necessite ~14-15 GB VRAM.", flush=True)

    print(f"Manifest: {TRAIN_JSONL}", flush=True)
    ds = DS(TRAIN_JSONL)
    print(f"Training clips: {len(ds):,}", flush=True)

    # SAFE_MODE (auto-recover OOM) : desactive eval-generation + batch reduit.
    # Active par WHISPER_SAFE_MODE=1 (relance par le pipeline apres un OOM).
    safe_mode = os.environ.get("WHISPER_SAFE_MODE", "0") == "1"
    if safe_mode:
        print("[SAFE_MODE] OOM recovery: batch=2, grad_accum=16, "
              "eval-generation DESACTIVEE (eval_loss seulement)", flush=True)

    eval_ds = None
    if os.path.exists(TEST_JSONL):
        eval_ds = EvalDS(TEST_JSONL, N_EVAL)
        print(f"Eval clips: {len(eval_ds)}", flush=True)

    model = WhisperForConditionalGeneration.from_pretrained(BASE)
    model.config.forced_decoder_ids = None
    model.config.suppress_tokens    = []
    model.generation_config.forced_decoder_ids = None
    model.config.forced_decoder_ids = proc.get_decoder_prompt_ids(
        language="arabic", task="transcribe")

    if eval_ds and cuda_ok:
        test_rows = [json.loads(l) for l in open(TEST_JSONL, encoding="utf-8")][:N_SANITY]
        model.to("cuda")
        sanity_check(model, test_rows, label="BEFORE_TRAIN")
        model.cpu()

    batch      = 2 if safe_mode else 4
    grad_accum = 16 if safe_mode else 8
    # En SAFE_MODE: eval garde le suivi de la loss mais SANS generation (cause OOM)
    eval_gen   = bool(eval_ds) and not safe_mode
    do_eval    = bool(eval_ds)
    best_metric = "wer" if eval_gen else ("loss" if do_eval else None)

    n_steps_per_epoch = len(ds) // (batch * grad_accum)
    eval_steps = min(1000, max(500, n_steps_per_epoch // 4))

    args = Seq2SeqTrainingArguments(
        output_dir=OUT,
        per_device_train_batch_size=batch,
        gradient_accumulation_steps=grad_accum,
        learning_rate=8e-6,
        warmup_steps=500,
        num_train_epochs=2,
        bf16=cuda_ok,
        fp16=False,
        logging_steps=200,
        save_strategy="steps" if do_eval else "epoch",
        save_steps=eval_steps if do_eval else None,
        save_total_limit=3,
        eval_strategy="steps" if do_eval else "no",
        eval_steps=eval_steps if do_eval else None,
        load_best_model_at_end=do_eval,
        metric_for_best_model=best_metric,
        greater_is_better=False,
        predict_with_generate=eval_gen,
        generation_max_length=440,
        report_to=[],
        dataloader_num_workers=8,          # Medium etait I/O-bound (GPU 1-3%) -> plus de workers
        dataloader_pin_memory=True,
        ignore_data_skip=True,             # reprise: ne PAS re-lire tous les audios (evite ~2h)
        remove_unused_columns=False,
        gradient_checkpointing=True,
        use_cpu=not cuda_ok,
    )

    callbacks = []
    if eval_ds:
        callbacks.append(EarlyStoppingCallback(early_stopping_patience=5))  # WER bruite -> plus tolerant

    trainer = Seq2SeqTrainer(
        model=model,
        args=args,
        train_dataset=ds,
        eval_dataset=eval_ds,
        data_collator=Collator(proc),
        # compute_metrics (WER) ne marche qu'avec generation; sinon eval_loss seul
        compute_metrics=make_compute_metrics() if eval_gen else None,
        processing_class=proc.feature_extractor,
        callbacks=callbacks if callbacks else None,
    )

    from transformers.trainer_utils import get_last_checkpoint
    last_ckpt = get_last_checkpoint(OUT) if os.path.isdir(OUT) else None
    if last_ckpt:
        print(f"\nReprise Medium depuis {last_ckpt} — eval_steps={eval_steps}", flush=True)
    else:
        print(f"\nDebut entrainement Medium — eval_steps={eval_steps}", flush=True)
    t0 = time.time()
    trainer.train(resume_from_checkpoint=last_ckpt)
    elapsed = time.time() - t0
    print(f"Entrainement termine en {elapsed/3600:.2f}h", flush=True)

    trainer.save_model(OUT)
    proc.save_pretrained(OUT)

    if eval_ds and cuda_ok:
        test_rows = [json.loads(l) for l in open(TEST_JSONL, encoding="utf-8")][:N_SANITY]
        sanity_check(model, test_rows, label="AFTER_TRAIN")

    print("WHISPER MEDIUM FT DONE ->", OUT, flush=True)


if __name__ == "__main__":
    main()
