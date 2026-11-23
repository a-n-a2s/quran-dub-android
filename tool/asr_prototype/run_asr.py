"""نموذج أولي لمحرك التعرف على التلاوة (يوم 3) — بيشتغل بـ GitHub Actions.

بيستخدم نفس المحرك (sherpa-onnx) ونفس النموذج (Abdou/quran-asr-tiny int8)
اللي رح ينضمّوا للتطبيق، بس عبر Python بدل Flutter، عشان نتأكد من الدقة
قبل الدمج على الجوال (يوم 4 حسب ملف المرجع).

لكل ملف صوت:
  1. "whole": تعرّف على المقطع كامل مرة وحدة.
  2. "vad": تقطيع على الوقفات بـ Silero VAD، وتعرّف على كل قطعة لحالها
     (هيك رح يشتغل التطبيق الحقيقي) مع توقيت كل حرف.
الناتج JSON بينقرا بـ tool/match_transcripts.dart للمطابقة مع القرآن.

usage: python run_asr.py MODEL_DIR VAD_MODEL CLIPS_JSON OUT_JSON
"""
import json
import sys
import time

import numpy as np
import sherpa_onnx
import soundfile as sf

SR = 16000


def char_times(tokens, timestamps, offset):
    """نص + توقيت لكل حرف (كل token بهالنموذج = حرف أو فاصل كلمة)."""
    text, times = [], []
    for tok, ts in zip(tokens, timestamps):
        t = tok.replace('▁', ' ')
        if t in ('<blk>', '<blank>', '<unk>', '<sos/eos>'):
            continue
        for ch in t:
            text.append(ch)
            times.append(round(offset + float(ts), 3))
    return ''.join(text), times


def decode(rec, samples, offset=0.0):
    s = rec.create_stream()
    s.accept_waveform(SR, samples)
    rec.decode_stream(s)
    r = s.result
    toks = list(getattr(r, 'tokens', []) or [])
    tss = list(getattr(r, 'timestamps', []) or [])
    if toks and len(toks) == len(tss):
        text, times = char_times(toks, tss, offset)
    else:
        text, times = r.text, []
    return {'text': text.strip() if not times else text, 'char_times': times,
            'raw_text': r.text}


def main():
    model_dir, vad_path, clips_path, out_path = sys.argv[1:5]
    rec = sherpa_onnx.OfflineRecognizer.from_zipformer_ctc(
        model=f'{model_dir}/model.int8.onnx',
        tokens=f'{model_dir}/tokens.txt',
        num_threads=2,
    )
    vad_cfg = sherpa_onnx.VadModelConfig()
    vad_cfg.silero_vad.model = vad_path
    vad_cfg.silero_vad.min_silence_duration = 0.35
    vad_cfg.silero_vad.min_speech_duration = 0.25
    vad_cfg.silero_vad.max_speech_duration = 25
    vad_cfg.sample_rate = SR
    window = vad_cfg.silero_vad.window_size

    clips = json.load(open(clips_path, encoding='utf-8'))
    out = []
    for c in clips:
        try:
            audio, sr = sf.read(c['wav'], dtype='float32')
        except Exception as e:  # noqa: BLE001
            print('skip', c['id'], e)
            continue
        assert sr == SR, sr
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        dur = len(audio) / SR

        t0 = time.time()
        whole = decode(rec, audio)
        t_whole = time.time() - t0

        t0 = time.time()
        vad = sherpa_onnx.VoiceActivityDetector(vad_cfg, buffer_size_in_seconds=120)
        segs = []
        i = 0
        while i < len(audio):
            vad.accept_waveform(audio[i:i + window])
            i += window
            while not vad.empty():
                segs.append((vad.front.start, np.array(vad.front.samples, dtype=np.float32)))
                vad.pop()
        vad.flush()
        while not vad.empty():
            segs.append((vad.front.start, np.array(vad.front.samples, dtype=np.float32)))
            vad.pop()
        seg_out = []
        for start, smp in segs:
            off = start / SR
            d = decode(rec, smp, off)
            d.update(start=round(off, 3), end=round(off + len(smp) / SR, 3))
            seg_out.append(d)
        t_vad = time.time() - t0

        print(f"[{c['id']}] {dur:.1f}s  whole RTF={t_whole/dur:.3f}  "
              f"vad segments={len(seg_out)} RTF={t_vad/dur:.3f}")
        print('   whole:', whole['text'][:160])
        out.append({**c, 'duration': round(dur, 2),
                    'rtf_whole': round(t_whole / dur, 4),
                    'rtf_vad': round(t_vad / dur, 4),
                    'whole': whole, 'segments': seg_out})

    json.dump(out, open(out_path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
