#!/bin/sh
# Fetches the MobileCLIP-S2 Core ML encoders and Apple's CLIP tokenizer assets.
# Run once before `xcodegen generate`. Idempotent: skips files that already
# exist with a plausible size. Models are gitignored (127 MB weight file).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS="$ROOT/Inventory/MLModels"
TOKENIZER_RES="$ROOT/Inventory/Support/MobileCLIP/Resources"
HF="https://huggingface.co/apple/coreml-mobileclip/resolve/main"
GH="https://raw.githubusercontent.com/apple/ml-mobileclip/main/ios_app/MobileCLIPExplore"

# fetch <url> <dest> <min-bytes>
fetch() {
    url="$1"; dest="$2"; min="$3"
    if [ -f "$dest" ] && [ "$(stat -f%z "$dest")" -ge "$min" ]; then
        echo "ok       $dest"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    echo "fetching $dest"
    curl -fsSL --retry 3 -o "$dest.part" "$url"
    size="$(stat -f%z "$dest.part")"
    if [ "$size" -lt "$min" ]; then
        echo "error: $dest is $size bytes, expected >= $min" >&2
        rm -f "$dest.part"
        exit 1
    fi
    mv "$dest.part" "$dest"
}

for enc in image text; do
    pkg="mobileclip_s2_${enc}.mlpackage"
    fetch "$HF/$pkg/Data/com.apple.CoreML/model.mlmodel" \
          "$MODELS/$pkg/Data/com.apple.CoreML/model.mlmodel" 100000
    fetch "$HF/$pkg/Data/com.apple.CoreML/weights/weight.bin" \
          "$MODELS/$pkg/Data/com.apple.CoreML/weights/weight.bin" 50000000
    fetch "$HF/$pkg/Manifest.json" "$MODELS/$pkg/Manifest.json" 300
done

fetch "$GH/Resources/clip-vocab.json"  "$TOKENIZER_RES/clip-vocab.json"  500000
fetch "$GH/Resources/clip-merges.txt"  "$TOKENIZER_RES/clip-merges.txt"  400000

echo "all MobileCLIP assets present"
