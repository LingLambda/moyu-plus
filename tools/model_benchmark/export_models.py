from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from ultralytics import YOLO


EXPORTS = (
    ("yolo26n", 16, "yolo26n_fp16.mlpackage"),
    ("yolo26n", 8, "yolo26n_int8.mlpackage"),
    ("yolo26s", 16, "yolo26s_fp16.mlpackage"),
)


def export_model(model_name: str, quantize: int, destination: Path) -> dict[str, object]:
    if destination.exists():
        return model_manifest(model_name, quantize, destination)

    model = YOLO(f"{model_name}.pt")
    exported = Path(
        model.export(
            format="coreml",
            imgsz=640,
            quantize=quantize,
            nms=False,
            batch=1,
            device="mps",
        )
    )
    if destination.exists():
        shutil.rmtree(destination)
    shutil.move(str(exported), destination)
    return model_manifest(model_name, quantize, destination)


def model_manifest(model_name: str, quantize: int, destination: Path) -> dict[str, object]:
    return {
        "model": model_name,
        "quantize": quantize,
        "path": str(destination),
        "size_bytes": sum(path.stat().st_size for path in destination.rglob("*") if path.is_file()),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("results/models"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    manifest = [
        export_model(model_name, quantize, args.output / filename)
        for model_name, quantize, filename in EXPORTS
    ]
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
