from __future__ import annotations

import argparse
import json
import statistics
import time
from pathlib import Path

from PIL import Image
from ultralytics import YOLO


def image_paths(directory: Path) -> list[Path]:
    suffixes = {".jpg", ".jpeg", ".png", ".heic", ".webp"}
    return sorted(path for path in directory.rglob("*") if path.suffix.lower() in suffixes)


def expected_count(path: Path, minimum_area_ratio: float) -> int | None:
    metadata = path.with_suffix(".json")
    if metadata.exists():
        value = json.loads(metadata.read_text(encoding="utf-8")).get("person_count")
        return int(value) if value is not None else None

    parts = list(path.parts)
    if "images" not in parts:
        return None
    parts[parts.index("images")] = "labels"
    label_path = Path(*parts).with_suffix(".txt")
    if not label_path.exists():
        return None

    count = 0
    for line in label_path.read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) >= 5 and fields[0] == "0":
            width, height = float(fields[3]), float(fields[4])
            count += int(width * height >= minimum_area_ratio)
    return count


def benchmark(
    model_path: Path,
    images: list[Path],
    confidence: float,
    minimum_area_ratio: float,
    repeats: int,
) -> dict[str, object]:
    model = YOLO(str(model_path), task="detect")
    timings: list[float] = []
    correct_two_person = 0
    labeled_two_person = 0
    false_two_person = 0
    labeled_single_person = 0
    non_risk_false_trigger = 0
    labeled_non_risk = 0
    per_image: list[dict[str, object]] = []

    if images:
        model.predict(Image.open(images[0]), conf=confidence, classes=[0], verbose=False)

    for image_path in images:
        counts: list[int] = []
        image = Image.open(image_path).convert("RGB")
        for _ in range(repeats):
            started = time.perf_counter()
            result = model.predict(image, conf=confidence, classes=[0], verbose=False)[0]
            timings.append((time.perf_counter() - started) * 1000)
            valid_boxes = 0
            for box in result.boxes:
                normalized = box.xyxyn[0]
                area = float((normalized[2] - normalized[0]) * (normalized[3] - normalized[1]))
                valid_boxes += int(area >= minimum_area_ratio)
            counts.append(valid_boxes)
        detected = round(statistics.median(counts))
        expected = expected_count(image_path, minimum_area_ratio)
        if expected is not None and expected >= 2:
            labeled_two_person += 1
            correct_two_person += int(detected >= 2)
        if expected == 1:
            labeled_single_person += 1
            false_two_person += int(detected >= 2)
        if expected is not None and expected < 2:
            labeled_non_risk += 1
            non_risk_false_trigger += int(detected >= 2)
        per_image.append({"image": str(image_path), "expected": expected, "detected": detected})

    sorted_timings = sorted(timings)
    p95_index = max(0, min(len(sorted_timings) - 1, int(len(sorted_timings) * 0.95) - 1))
    return {
        "model": str(model_path),
        "image_count": len(images),
        "repeat_count": repeats,
        "latency_ms_p50": statistics.median(timings) if timings else None,
        "latency_ms_p95": sorted_timings[p95_index] if timings else None,
        "two_person_recall": correct_two_person / labeled_two_person if labeled_two_person else None,
        "single_person_false_trigger_rate": false_two_person / labeled_single_person if labeled_single_person else None,
        "non_risk_false_trigger_rate": non_risk_false_trigger / labeled_non_risk if labeled_non_risk else None,
        "labeled_two_person_images": labeled_two_person,
        "labeled_non_risk_images": labeled_non_risk,
        "images": per_image,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", type=Path, default=Path("results/models"))
    parser.add_argument("--images", type=Path, default=Path("data/images"))
    parser.add_argument("--output", type=Path, default=Path("results/benchmark.json"))
    parser.add_argument("--confidence", type=float, default=0.25)
    parser.add_argument("--minimum-area-ratio", type=float, default=0.012)
    parser.add_argument("--repeats", type=int, default=5)
    args = parser.parse_args()

    models = sorted(args.models.glob("*.mlpackage"))
    images = image_paths(args.images)
    if not models:
        raise SystemExit(f"No .mlpackage models found in {args.models}")
    if not images:
        raise SystemExit(f"No benchmark images found in {args.images}")

    results = [
        benchmark(path, images, args.confidence, args.minimum_area_ratio, args.repeats)
        for path in models
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
