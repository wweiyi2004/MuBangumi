"""Download pinned public ONNX assets; verify upstream Git/LFS hashes.

No remote Python code, pickle, login, or inference service is used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

HERE = Path(__file__).resolve().parent
DEFAULT_DATA = HERE.parent / "recommend_dataset/data/semantic_bge_v1"


def verify(path: Path, entry: dict) -> bool:
    if not path.is_file() or path.stat().st_size != entry["size"]:
        return False
    content = path.read_bytes()
    if "sha256" in entry:
        return hashlib.sha256(content).hexdigest() == entry["sha256"]
    return hashlib.sha1(f"blob {len(content)}\0".encode() + content).hexdigest() == entry["git_blob"]


def download(destination: Path, *, reference: bool = False) -> None:
    manifest = json.loads((HERE / "model.lock.json").read_text(encoding="utf-8"))
    destination.mkdir(parents=True, exist_ok=True)
    for entry in manifest["files"]:
        if entry["path"] == "onnx/model.onnx" and not reference:
            continue
        target = destination / entry["path"]
        if verify(target, entry):
            print(f"verified {entry['path']}", flush=True)
            continue
        if target.exists():
            raise ValueError(f"Unexpected content: {target}; choose a new directory")
        target.parent.mkdir(parents=True, exist_ok=True)
        url = f"https://huggingface.co/{manifest['repository']}/resolve/{manifest['revision']}/{entry['path']}"
        temporary = target.with_suffix(target.suffix + ".partial")
        print(f"downloading {entry['path']} ({entry['size']} bytes)", flush=True)
        with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as output:
            size = 0
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > entry["size"]:
                    raise ValueError("Download exceeded pinned size")
                output.write(chunk)
        if not verify(temporary, entry):
            raise ValueError(f"Hash verification failed: {temporary}")
        temporary.replace(target)
    (destination / "source.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_DATA / "model")
    parser.add_argument("--reference", action="store_true", help="Also fetch FP32 for quantization comparison")
    args = parser.parse_args()
    download(args.output, reference=args.reference)
