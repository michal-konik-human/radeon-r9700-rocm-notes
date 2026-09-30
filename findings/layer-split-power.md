# Four 250 W cards running a 235B model draw ~470 W, not 1000 W

With `-sm layer` the model is cut into consecutive slices, so each token passes through the
cards **one after another** — each card is busy only part of the time.

Summed power of the four R9700s (netdata, 1 s), 30 Sep 2026, 3 runs each of pp512/tg128 and
pp4096/tg1024 including model loads:

| Model | median (active) | peak | per-card median, first → last card |
|---|---:|---:|---|
| Qwen3-235B-A22B UD-Q3_K_XL | 490 W | 630 W | 96 / 102 / 132 / **162** W |
| DeepSeek-V4-Flash UD-IQ3_XXS | 394 W | 931 W | 61 / 81 / 102 / **147** W |

The **last card in the chain works hardest**. When sizing a PSU for layer-split inference,
the sum of the caps is the wrong number; for tensor-parallel it would not be.
