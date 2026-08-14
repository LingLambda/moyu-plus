# YOLO26 模型导出与基准

该目录使用 `uv` 创建独立的 Python 3.12 环境。默认优先使用阿里云 PyPI 镜像；若某个新版本尚未同步，可临时覆盖为官方源：

```bash
UV_DEFAULT_INDEX=https://pypi.org/simple uv sync
```

## 初始化

```bash
cd tools/model_benchmark
uv python install 3.12
uv sync
```

## 导出

```bash
uv run python export_models.py
```

生成：

- `results/models/yolo26n_fp16.mlpackage`
- `results/models/yolo26n_int8.mlpackage`
- `results/models/yolo26s_fp16.mlpackage`

## 静态素材基准

将测试图片放到 `data/images`。工具支持 Ultralytics 数据集的 `images` / `labels` 目录结构，也可以在同名 JSON 中直接标注可见人体数量：

```json
{"person_count": 2}
```

然后运行：

```bash
uv run python benchmark_models.py
```

工具默认采用与 App 一致的 `0.25` 置信度和 `1.2%` 最小框面积，输出 p50/p95 延迟、多人场景召回和单人错误触发率。最终胜出模型复制为仓库 `Models/yolo26n.mlpackage` 后重新运行 `xcodegen generate`。

真实摄像头侧后方进入、遮挡和背景经过仍需双人场景测试，静态素材不能替代该验收。
