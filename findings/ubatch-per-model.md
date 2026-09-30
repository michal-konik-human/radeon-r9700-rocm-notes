# `--ubatch-size`: the default (512) was never the best, and "bigger" can be much worse

Prompt processing of 4096 tokens, `llama-bench -fa 1 -b 4096 -ub 256,512,1024,2048,4096 -r 2`,
each model on the number of R9700s it is served on, llama.cpp `680a036`, 250 W cap:

| Model | Cards | ub 256 | ub 512 | ub 1024 | ub 2048 | ub 4096 | best vs 512 |
|---|---|---:|---:|---:|---:|---:|---|
| Qwen3-235B-A22B UD-Q3_K_XL | 4 | 389 | 571 | 723 | 812 | **894** | **+57 %** |
| DeepSeek-V4-Flash UD-IQ3_XXS | 4 | 510 | 838 | **1135** | 713 | 353 | +35 % (4096: **−58 %** vs 1024) |
| Laguna S 2.1 UD-Q4_K_XL | 3 | 1169 | 1575 | 1889 | 2004 | 2027 | +29 % |
| gpt-oss-120b MXFP4 | 3 | 4169 | 4712 | **5559** | 5068 | 3605 | +18 % |
| gpt-oss-20b MXFP4 | 1 | 4232 | 5373 | 5942 | **6359** | 6149 | +18 % |
| Qwen3-Next-80B-A3B Q4_1 | 2 | 3536 | 3977 | **4327** | 3912 | 2853 | +9 % |
| Bielik-11B Q8_0 (dense) | 1 | 2596 | 2840 | 2989 | **3061** | 3058 | +8 % |
| Qwen3-32B Q4_K_M (dense) | 1 | 808 | 883 | 909 | 919 | 920 | +4 % |
| gpt-oss-20b on CPU (8 threads) | — | 110 | 108 | 110 | 109 | — | none |

(tok/s)

- **Dense models barely care; large MoEs care a lot — in opposite directions.**
- Decode throughput does not depend on ubatch.
- A larger ubatch costs VRAM for compute buffers. Rule used for serving: the **smallest**
  value within 2 % of the best.
