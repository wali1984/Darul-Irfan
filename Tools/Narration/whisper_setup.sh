#!/usr/bin/env bash
# Whisper's own environment on the SATA disk (home is 92% full), kept apart
# from urdu-ocr/.venv so the OCR pipeline's pinned packages are never touched.
set -euo pipefail
W=/mnt/sata1tb/di-whisper
mkdir -p "$W/hf" "$W/cuda-libs" "$W/pip-cache"
export PIP_CACHE_DIR="$W/pip-cache" HF_HOME="$W/hf"

[ -x "$W/.venv/bin/python" ] || python3 -m venv "$W/.venv"
"$W/.venv/bin/pip" install --quiet --upgrade pip
# CTranslate2 (under faster-whisper) runs on CUDA 12 cuBLAS and cuDNN 9; the
# driver (580, CUDA 13) runs CUDA 12 libraries, so they come from pip here.
"$W/.venv/bin/pip" install --quiet faster-whisper "nvidia-cublas-cu12" "nvidia-cudnn-cu12>=9,<10"

site=$("$W/.venv/bin/python" -c "import site; print(site.getsitepackages()[0])")
for lib in "$site"/nvidia/cublas/lib/*.so* "$site"/nvidia/cudnn/lib/*.so*; do
  ln -sf "$lib" "$W/cuda-libs/"
done

"$W/.venv/bin/python" - <<'PY'
from huggingface_hub import snapshot_download
path = snapshot_download("Systran/faster-whisper-large-v3")
print("model ready at", path)
PY
"$W/.venv/bin/python" -c "import ctranslate2, faster_whisper; print('ctranslate2', ctranslate2.__version__, 'faster-whisper', faster_whisper.__version__)"
