# Core ML 模型

此目录在构建时作为应用资源目录。将基准胜出的模型放在这里，并使用以下稳定名称之一：

- `yolo26n.mlpackage`
- `yolo26n_int8.mlpackage`
- `yolo26s.mlpackage`

运行时使用的 `yolo26s.mlpackage` 已纳入仓库，以保证 GitHub CI 和 DMG 发布可重复构建。
其他模型二进制和训练权重不提交到仓库。生成步骤见 `tools/model_benchmark/README.md`。
