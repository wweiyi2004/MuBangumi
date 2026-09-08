# 现成 BGE 中文番剧检索原型

直接使用 `BAAI/bge-small-zh-v1.5` 的现成 ONNX 导出，**不训练、不微调**。
本工具负责固定目录上的离线检索验证，尚未接入 Flutter，也未进行手机性能验收。

实际结果与限制见 [本轮验证记录](../../docs/qa/SEMANTIC_BGE_BASELINE.md)。已完成两种文本构造的对照，
不微调的简介方案 Hit@10 较好，但前 5 排序仍待改进，不能直接作为上线验收结果。

## 已实现

- 读取现有 `item_features.jsonl`，只处理公开作品资料，不读取用户收藏、交互、凭证。
- 将名称、别名、题材标签和简介组合为检索文本；不将评分、排名、热度送入编码器。
- 正片集数取资料中的 `infobox.话数`，避免将包含额外章节的 `episode_count` 当作正片集数。
  只接受无歧义的整数；未知值在硬性集数条件下被排除。
- 下载固定提交的中文 BGE INT8 / FP32 ONNX，校验上游 Git blob / LFS SHA-256。
- 按 BGE 官方方式，对查询加检索前缀，取 CLS 并 L2 归一化；作品不加查询前缀。
- 作品向量离线生成，缓存按文本和编码器哈希校验。原型取最多 384 tokens，包含特殊 token。
- 512 维作品向量支持逐行 INT8 存储；携带缩放系数、ID、模型版本与文件哈希。
- 按显式参数执行年份、正片集数、作品 ID、平台、已知标签排除；再按相似度和名称去重排序。
- 比较相同目录上的应用规则评分、字符 TF-IDF、BGE FP32、BGE INT8 与 INT8 作品向量。
- 生成 JSON 和 Markdown 报告，以及可在电脑离线查询的独立模型与向量包。

## 评估边界

`evaluation_queries.json` 包含 **50 条开发查询和 3 条未评分的边界探针**，由助手在查看模型排序前编写。
42 条主要是根据已有剧情资料改写的具体需求，4 条为宽泛偏好，4 条附带显式条件。
已知正例根据资料选取，**不是完整相关性标注，也不是来自真实用户的独立测试集**。
报告只使用已知正例的 Hit@K / MRR@10，不能把它们解释成推荐准确率或满意度。
未来若据此调整文本、阈值或参数，此数据集仍仅作开发集，需要另建未参与调整的用户测试集。

条件查询的 `retrieval_text` 和 `filters` 是人工预先拆分的，**没有实现通用自然语言条件解析**。
例如 `--exclude-tag 致郁` 只能排除已标注这个标签的作品，缺少标签不意味着没有悲剧情节。
也未实现域外输入拒绝：只计算最近邻时，即使输入修车问题也会返回番剧。

应用规则对照使用空偏好、相同完整作品目录和相同显式过滤。它复现本地评分部分，
不包含线上 Bangumi API 的候选召回、默认最低评分或真实用户个性化，不能作为完整应用的端到端对比。
`verify_app_reference.dart` 可对全部案例逐作品核对 Python 评分是否与真实 Dart 引擎一致。

## 运行（项目根目录，PowerShell）

推荐 Python 3.13；需要的包只有 CPU 推理和评估依赖，不需要 PyTorch / CUDA。
所有新环境、缓存和生成文件放 E 盘工作区，避免占用系统盘。

```powershell
$env:UV_CACHE_DIR = Join-Path $PWD '.dart_tool/semantic-cache/uv'
$env:UV_PYTHON_INSTALL_DIR = Join-Path $PWD '.dart_tool/semantic-cache/python'
uv venv .dart_tool/semantic-venv --python 3.13
uv pip install --python .dart_tool/semantic-venv/Scripts/python.exe `
  --index-url https://pypi.org/simple -r tool/semantic_retrieval/requirements.txt

# 唯一需要联网的步骤：下载模型；--reference 额外下载 FP32 用于量化对照。
.dart_tool/semantic-venv/Scripts/python.exe -X utf8 tool/semantic_retrieval/download_model.py --reference

# 下列过程只读本地模型与数据，不联网、不训练。
$env:OMP_NUM_THREADS = '4'
$env:OPENBLAS_NUM_THREADS = '4'
.dart_tool/semantic-venv/Scripts/python.exe -X utf8 tool/semantic_retrieval/run.py --reference
.dart_tool/semantic-venv/Scripts/python.exe -m pytest tool/semantic_retrieval/tests -q

.dart_tool/semantic-venv/Scripts/python.exe -X utf8 tool/semantic_retrieval/search.py `
  '想看女孩子一起组乐队，慢慢克服不善交际的问题' --max-episodes 12 --limit 5

# 第二轮诊断：保留初始结果，单独生成简介优先的文本与向量。
.dart_tool/semantic-venv/Scripts/python.exe -X utf8 tool/semantic_retrieval/run.py `
  --text-profile synopsis --output tool/recommend_dataset/data/semantic_bge_synopsis_v1
.dart_tool/semantic-venv/Scripts/python.exe -X utf8 tool/semantic_retrieval/search.py `
  '不善交际的女孩通过乐队认识伙伴' --max-episodes 12 `
  --bundle tool/recommend_dataset/data/semantic_bge_synopsis_v1/bundle

# 真实包的哈希、向量与推理验证；可额外传 --dart-reference 核对应用评分。
.dart_tool/semantic-venv/Scripts/python.exe -X utf8 tool/semantic_retrieval/verify_artifacts.py
```

默认输入为 `tool/recommend_dataset/data/expand_v1/export_all/item_features.jsonl`；可用 `--input` 覆盖。
默认输出 `tool/recommend_dataset/data/semantic_bge_v1/`，已由项目的 `data/` 规则忽略：

- `corpus_report.json`：覆盖率、话数差异与数据 SHA-256。
- `report.json` / `report.md`：汇总、分组、每条查询排序和量化差异。
- `bundle/`：INT8 模型、分词器、量化作品向量、元数据及完整性清单。
- `model/` / `embeddings_*.npy`：本地原始下载与缓存，不用于直接发布。

`search.py` 每次启动会核验全部包文件，因此打印的加载时间包括校验；模型常驻后的耗时见评估报告。
当前 Python 原型把量化作品向量还原为浮点用于点积，文件大小不等于工作内存。
所有耗时均为当前 Windows CPU 的观测值，不能代替 Android 真机测量。

## 接入应用之前

1. 人工盲评宽泛偏好、圈内表达、否定条件与冷门作品，补充缺失或有噪声的资料。
2. 将可解析的硬性条件展示为可修改条件，未识别的要求不得静默宣称已满足。
3. 处理域外输入、低相关结果、同系列多条、已收藏 / 隐藏作品及模型更新兼容。
4. 实测 Android 的推理库增量、总模型包、峰值内存、冷启动和短查询 P50/P95。
5. 模型约 24 MB，作品向量和运行库另计；现成方案不满足原先 10 MB 总预算。
6. 只有独立评估证明领域误匹配持续存在且有足够标注时，再决定是否微调。

模型上游：[BGE 官方用法与 MIT 标识](https://huggingface.co/BAAI/bge-small-zh-v1.5)，
[固定 ONNX 版本](https://huggingface.co/Xenova/bge-small-zh-v1.5/tree/75c43b069aac4d136ba6bc1122f995fedcfd2781)。
模型与作品资料的分发说明须在正式发布时一并整理；本次产物仅作本地研究验证。
