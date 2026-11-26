#!/usr/bin/env python3
"""PitchDetector (MPM/NSDF) numeric replica — mirrors AcousticReference/Audio/PitchDetector.swift
step-for-step: DC removal, RMS gate, NSDF via autocorrelation + recursive divisor (float64),
identical peak-picking loops, 0.58 clarity gate, 0.88 threshold, parabolic interpolation.
Swift FFT autocorrelation is mathematically the linear autocorrelation used here (numpy, float64);
Swift divisor recursion is float64 in both. NSDF storage: Swift Double vs web Float32 — replica uses float64 (= Swift).
"""
import numpy as np

SR = 48000.0
CLARITY = 0.58
RATIO = 0.88

def detect(samples, sr, min_freq, max_freq, rms_gate):
    x = np.asarray(samples, dtype=np.float64)
    n = len(x)
    if n < 4:
        return None, 0.0, 0.0
    x = x - x.mean()
    rms = float(np.sqrt(np.mean(x * x)))
    if rms < rms_gate:
        return None, 0.0, rms
    min_tau = max(2, int(np.floor(sr / max_freq)))
    max_tau = min(n // 2, int(np.ceil(sr / min_freq)))
    if max_tau <= min_tau:
        return None, 0.0, rms
    # linear autocorrelation r(tau) = sum_i x[i] x[i+tau]
    acf = np.correlate(x, x, mode='full')[n - 1: n + max_tau]  # acf[0..maxTau]
    nsdf = np.zeros(max_tau + 1)
    divisor = 2.0 * acf[0]
    for tau in range(1, max_tau + 1):
        a = x[tau - 1]; b = x[n - tau]
        divisor -= a * a + b * b
        if tau >= min_tau:
            nsdf[tau] = (2.0 * acf[tau]) / divisor if divisor > 0 else 0.0
    peaks = []
    global_max = 0.0
    tau = min_tau
    while tau <= max_tau and nsdf[tau] > 0: tau += 1
    while tau <= max_tau and nsdf[tau] <= 0: tau += 1
    cur_tau, cur_val = -1, -1.0
    while tau <= max_tau:
        if nsdf[tau] > 0:
            if nsdf[tau] > cur_val:
                cur_val = nsdf[tau]; cur_tau = tau
        elif cur_tau != -1:
            peaks.append((cur_tau, cur_val))
            global_max = max(global_max, cur_val)
            cur_tau, cur_val = -1, -1.0
        tau += 1
    if cur_tau != -1:
        peaks.append((cur_tau, cur_val))
        global_max = max(global_max, cur_val)
    if not peaks or global_max < CLARITY:
        return None, global_max, rms
    threshold = RATIO * global_max
    chosen = next((p for p in peaks if p[1] >= threshold), peaks[0])
    t = chosen[0]
    refined = float(t)
    if min_tau < t < max_tau:
        y1, y2, y3 = nsdf[t - 1], nsdf[t], nsdf[t + 1]
        denom = y1 - 2 * y2 + y3
        if abs(denom) > 1e-6:
            refined = t + 0.5 * (y1 - y3) / denom
    return sr / refined, global_max, rms

def cents(est, true):
    return 1200.0 * np.log2(est / true)

def harmonic_tone(freq, dur, sr=SR, harmonics=(1.0, 0.6, 0.35, 0.2, 0.12, 0.07), phase=0.0):
    t = np.arange(int(dur * sr)) / sr
    y = np.zeros_like(t)
    for k, a in enumerate(harmonics, start=1):
        y += a * np.sin(2 * np.pi * freq * k * t + phase)
    peak = np.max(np.abs(y))
    return y / peak * 0.7

def frames_of(sig, n, hop):
    out = []
    for start in range(0, len(sig) - n + 1, hop):
        out.append(sig[start:start + n])
    return out

def run_case(name, sig, true_freq, n, bounds, gate=0.009, hop=1024):
    errs, rej = [], 0
    for fr in frames_of(sig, n, hop):
        f, _, _ = detect(fr, SR, bounds[0], bounds[1], gate)
        if f is None:
            rej += 1
        else:
            errs.append(cents(f, true_freq))
    if errs:
        e = np.array(errs)
        print(f"{name:44s} frames={len(errs)+rej:3d} rej={rej:3d} "
              f"med={np.median(e):+7.3f}c p95|e|={np.percentile(np.abs(e),95):6.3f}c max|e|={np.max(np.abs(e)):6.3f}c")
    else:
        print(f"{name:44s} ALL REJECTED (rej={rej})")
    return errs

rng = np.random.default_rng(42)
print("=== A. Pure sine, reference pitches (N=4096, bounds 100-1500) ===")
for f in (440.0, 442.0):
    t = np.arange(int(0.5 * SR)) / SR
    run_case(f"sine {f} Hz", 0.7 * np.sin(2 * np.pi * f * t), f, 4096, (100, 1500))

print("=== B. Harmonic tones across range ===")
run_case("harmonic 110.00 (A2, N=8192, b 80-600)", harmonic_tone(110.0, 0.6), 110.0, 8192, (80, 600))
run_case("harmonic 196.00 (G3, N=4096, b 100-1500)", harmonic_tone(196.0, 0.5), 196.0, 4096, (100, 1500))
run_case("harmonic 220.00 (A3)", harmonic_tone(220.0, 0.5), 220.0, 4096, (100, 1500))
run_case("harmonic 440.00 (A4)", harmonic_tone(440.0, 0.5), 440.0, 4096, (100, 1500))
run_case("harmonic 880.00 (A5)", harmonic_tone(880.0, 0.5), 880.0, 4096, (100, 1500))
run_case("harmonic 1046.50 (C6)", harmonic_tone(1046.5, 0.5), 1046.5, 4096, (100, 1500))
run_case("harmonic 55.00 (A1, N=16384, b 32-300)", harmonic_tone(55.0, 1.2), 55.0, 16384, (32, 300))
run_case("harmonic 1567.98 (G6, N=4096, b 200-3000)", harmonic_tone(1567.98, 0.5), 1567.98, 4096, (200, 3000))

print("=== C. Known detune (measure the detune itself) ===")
for dc in (+5.0, +10.0, -7.0, +25.0):
    f = 440.0 * 2 ** (dc / 1200.0)
    run_case(f"harmonic 440 {dc:+.0f}c", harmonic_tone(f, 0.5), f, 4096, (100, 1500))

print("=== D. Noise (SNR on harmonic 440) ===")
base = harmonic_tone(440.0, 0.5)
sig_p = np.mean(base ** 2)
for snr in (20, 10):
    noise = rng.normal(0, np.sqrt(sig_p / 10 ** (snr / 10)), len(base))
    run_case(f"harmonic 440 + noise {snr} dB SNR", base + noise, 440.0, 4096, (100, 1500))

print("=== E. Strong 2nd harmonic / odd-harmonic (octave guard) ===")
run_case("H2>H1 (0.5,1.0,0.3) 220", harmonic_tone(220.0, 0.5, harmonics=(0.5, 1.0, 0.3, 0.15)), 220.0, 4096, (100, 1500))
run_case("clarinet odd-only 233.08", harmonic_tone(233.08, 0.5, harmonics=(1.0, 0.0, 0.55, 0.0, 0.28, 0.0, 0.1)), 233.08, 4096, (100, 1500))

print("=== F. Hard clipping (ff overload, peak=1.0 clip 0.75) ===")
clip = np.clip(harmonic_tone(196.0, 0.5) / 0.7, -0.75, 0.75)
run_case("clipped harmonic 196", clip, 196.0, 4096, (100, 1500))
t = np.arange(int(0.5 * SR)) / SR
clip2 = np.clip(np.sin(2 * np.pi * 440 * t), -0.6, 0.6)
run_case("clipped sine 440", clip2, 440.0, 4096, (100, 1500))

print("=== G. Vibrato tracking (440 +-35c @ 5.5 Hz, per-frame vs instantaneous) ===")
dur = 1.2
t = np.arange(int(dur * SR)) / SR
inst_cents = 35.0 * np.sin(2 * np.pi * 5.5 * t)
phase = 2 * np.pi * 440.0 * np.cumsum(2 ** (inst_cents / 1200.0)) / SR
vib = 0.7 * np.sin(phase)
n, hop = 4096, 1024
track_err = []
for start in range(0, len(vib) - n + 1, hop):
    f, _, _ = detect(vib[start:start + n], SR, 100, 1500, 0.009)
    if f is None:
        continue
    center = start + n // 2
    true_c = 1200 * np.log2(440.0 * 2 ** (inst_cents[center] / 1200.0) / 440.0)
    track_err.append(cents(f, 440.0) - true_c)
te = np.array(track_err)
print(f"vibrato frames={len(te)} med={np.median(te):+.2f}c p95|e|={np.percentile(np.abs(te),95):.2f}c max|e|={np.max(np.abs(te)):.2f}c "
      f"(window smearing expected: window spans {n/SR*1000:.0f} ms of a 182 ms vibrato period)")

print("=== H. Quiet pp tone near gate (RMS ~0.012, gate mid 0.009) ===")
q = harmonic_tone(440.0, 0.5) * (0.012 / 0.35)
run_case("quiet harmonic 440 (rms~0.012)", q, 440.0, 4096, (100, 1500))
