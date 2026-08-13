# MuBangumi 番剧推荐训练集与基线模型

为 Implicit ALS + 内容冷启动推荐模型构建**可重复、可增量、可审计**的数据集。
第一阶段负责采集、清洗、导出与基础统计；阶段 1.5 增加交互引用补抓、严格时间切分、
TF-IDF 内容推荐基线、离线评测与训练准入门槛。阶段 2 为个人研究提供低频的公开社区作者
种子发现器，用来扩大交互样本；当前已增加第一版 Implicit ALS 训练、验证集变体选择和
逐用户全目录测试。**尚未接入 Flutter 页面。**

- 数据来源：Bangumi 官方公开 API（`api.bgm.tv`）；种子发现另用正常可访问的
  `next.bgm.tv/p1` 社区 JSON。P1 并非稳定 OpenAPI，结构可能变化。
- 不抓 HTML、不登录、不绕过 Cloudflare/Turnstile；遇到 401/403 或验证页面立即停止。
- 输出：`subjects.csv` / `interactions.csv` / 时间切分的训练·验证·测试交互文件 /
  `item_features.jsonl` / `dataset_report.json` / `checkpoints.sqlite` / `failed_requests.jsonl` /
  `baseline_report.json` / `feature_matrix.npz` / `als_report.json` / ALS 模型与 ID 映射。
- 所有生成数据（`data/`、venv、salt、seed_users.txt、本地配置）已加入 `.gitignore`，不会进入 Git。

## 目录结构

```text
tool/recommend_dataset/
├─ collect_user_seeds.py      # 低频发现公开社区话题/回复作者（本地研究种子）
├─ collect_subjects.py        # 采集番剧条目（普通枚举 + --from-interactions 补抓）
├─ collect_interactions.py    # 采集 seed 用户的公开番剧收藏（隐式反馈）
├─ export_dataset.py          # 导出数据集 + dataset_report.json（严格时间切分）
├─ check_dataset.py           # ALS 训练准入门槛（exit 0/2/1）
├─ run_content_baseline.py    # TF-IDF 内容推荐基线 + 离线评测
├─ run_als_baseline.py        # ALS 验证选型、Train+Validation 重训、锁定测试
├─ run_als_cv.py              # 三个历史季度的 rolling-origin 时间交叉验证
├─ dataset_config.example.json# 配置模板（复制为 dataset_config.json 使用）
├─ seed_users.txt             # 原始种子（每行一个，# 注释；已被 gitignore）
├─ seed_users_stage2.txt      # 发现后合并种子（自动生成；已被 gitignore）
├─ requirements.txt
├─ src/
│  ├─ config.py               # 配置加载与校验（路径相对配置文件解析）
│  ├─ http_client.py          # 限速客户端：全局 QPS、指数退避+抖动、Retry-After
│  ├─ bangumi.py              # API 端点 + pydantic 响应校验（个人字段在模型层丢弃）
│  ├─ parse.py                # 日期/季度/infobox/标签解析（缺失字段防御式处理）
│  ├─ anon_id.py              # 匿名用户 ID：本地盐化 SHA-256
│  ├─ weights.py              # 隐式反馈权重（收藏类型 × 评分修正）
│  ├─ db.py                   # SQLite：upsert 去重、checkpoint、known_subjects、run_stats
│  ├─ splits.py               # 严格时间切分（updated_at UTC）与条目标记
│  └─ export.py               # CSV/JSONL 导出与统计报告
├─ baseline/
│  ├─ features.py             # 稀疏内容特征（命名空间 token、中文 char n-gram、严格模式）
│  ├─ content_model.py        # TF-IDF 模型（sparse csr，保存 npz/npy）
│  ├─ als_model.py            # ALS 置信矩阵、训练、逐用户排名与模型持久化
│  ├─ evaluate.py             # 用户画像、候选集、评分排序
│  └─ metrics.py              # Recall/NDCG/HitRate/MRR/Catalog Coverage
└─ tests/                     # 单元测试（本地 fixture + 127.0.0.1 mock，无外部网络）
```

## 环境要求与安装

- Python 3.11+（本项目在 Windows 11 + Python 3.14 上验证；系统默认 `python` 可能是 3.10，
  请用 `py -3.14` 或 `py -3.13` 指定版本）。
- 注意：默认 pip 镜像（清华）可能缺 Python 3.14 的 scikit-learn wheel，若安装失败请加
  `-i https://pypi.org/simple`。

```powershell
cd tool\recommend_dataset
py -3.14 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## 使用（命令一览）

```powershell
# 1. 采集番剧条目（普通枚举：日历 + 季度搜索）
python tool\recommend_dataset\collect_subjects.py --config tool\recommend_dataset\dataset_config.json

# 1b. 补抓：交互引用了但 subjects 缺失的动画（只补缺失，断点续跑，幂等）
python tool\recommend_dataset\collect_subjects.py --config ... --from-interactions
python tool\recommend_dataset\collect_subjects.py --config ... --from-interactions --limit 500
python tool\recommend_dataset\collect_subjects.py --config ... --from-interactions --dry-run
python tool\recommend_dataset\collect_subjects.py --config ... --from-interactions `
  --priority value --metadata-only --limit 500
python tool\recommend_dataset\collect_subjects.py --config ... --from-interactions --failed-only
python tool\recommend_dataset\collect_subjects.py --config ... --from-interactions `
  --cold-eval --metadata-only --limit 300

# 2. 采集交互
python tool\recommend_dataset\collect_interactions.py --config ... --users seed_users.txt
python tool\recommend_dataset\collect_interactions.py --config ... `
  --users seed_users_stage2.txt --limit 300
python tool\recommend_dataset\collect_interactions.py --config ... `
  --users seed_users_stage2.txt --new-users-first --limit 200

# 2a. 阶段 2：先预览，不联网、不写文件
python tool\recommend_dataset\collect_user_seeds.py --config ... --dry-run

# 2b. 从公开社区 JSON 发现作者，合并原始种子，目标 600 人
python tool\recommend_dataset\collect_user_seeds.py --config ... --target-users 600

# 2c. 使用扩充后的本地种子采集公开收藏
python tool\recommend_dataset\collect_interactions.py --config ... --users seed_users_stage2.txt

# 3. 导出数据集（严格时间切分）
python tool\recommend_dataset\export_dataset.py --config ...

# 4. ALS 训练准入检查（0=通过 / 2=数据不足但结构有效 / 1=损坏）
python tool\recommend_dataset\check_dataset.py --config ...; echo $LASTEXITCODE

# 5. TF-IDF 内容基线 + 离线评测
python tool\recommend_dataset\run_content_baseline.py --config ...

# 6. Implicit ALS：all / regular / core 三种可复现实验视图
python tool\recommend_dataset\run_als_baseline.py --config ...
python tool\recommend_dataset\run_als_baseline.py --config ... --view regular
python tool\recommend_dataset\run_als_baseline.py --config ... --view core

# 6b. 时间交叉验证：只用历史季度选型，不查看测试窗口
python tool\recommend_dataset\run_als_cv.py --config ... --view all
python tool\recommend_dataset\run_als_cv.py --config ... --view core

# 可复现的扩展版参数搜索；每个参数都只看三个历史验证季度
python tool\recommend_dataset\run_als_cv.py --config dataset_config.expand_uncapped_v1.json `
  --negative-scales 0.25 --half-lives 0 365 730 1460 2920
python tool\recommend_dataset\run_als_cv.py --config dataset_config.expand_uncapped_v1.json `
  --negative-scales 0.25 --half-lives 365 --regularizations 0.02 0.05 0.1 0.2
python tool\recommend_dataset\run_als_cv.py --config dataset_config.expand_uncapped_v1.json `
  --negative-scales 0.25 --half-lives 365 --regularizations 0.1 --factors 32 64 96

# 冻结参数后训练一次最终候选，再与旧模型做相同用户/相关项/候选目录的公平比较
python tool\recommend_dataset\run_als_baseline.py --config dataset_config.expand_recency_v1.json
python tool\recommend_dataset\compare_als_common.py `
  --baseline-config dataset_config.eval2025.json `
  --candidate-config dataset_config.expand_recency_v1.json

# 7. 测试
python -m pytest tool\recommend_dataset\tests
```

**断点续跑**：任何步骤中断后直接重跑同一命令即可——条目的 per-id 状态、搜索分页游标、
每个用户合并收藏流的分页 offset、API total、完成标志和停止原因都保存在 `checkpoints.sqlite`；补抓模式下 `claim`
的占位行本身就是断点状态，重复执行不产生重复行（upsert 幂等）。

`max_pages_per_run` 只是单次运行预算：触达预算会记为 `truncated`，下次从 offset 续采；
只有 API 返回的 `total` 证明到达流末尾时才记为 `complete`。旧版 `status=ok` 因未保存 total，
迁移后一律视为未验证完整，避免把“正好停在 200 条”误当成完整用户。

**刷新数据**：交互采集加 `--refetch` 清空（用户×类型）游标重新抓取；补抓加
`--failed-only` 只重试失败条目。

**删除数据**：删除 `tool\recommend_dataset\data\` 即可清空采集结果、salt、断点与基线产物。

## 阶段 2：公开社区作者种子发现

`collect_user_seeds.py` 顺序读取 `next.bgm.tv/p1/groups/-/topics` 的公开话题列表与话题详情，
只提取 `creator.username`，包括原帖、一级回复与嵌套回复作者。默认行为：

- 读取 `seed_users.txt` 与既有 `seed_users_stage2.txt`，去重后写回后者；
- 目标 600 人，最多 20 个话题列表页、400 个话题详情、每页 50 条；
- 复用配置中的全局限速且强制 `QPS <= 1`、单线程；429/5xx 按既有退避策略重试；
- 进度写入 `data/user_seed_discovery.json`，每个话题后保存，可直接重跑；
- 控制台、失败日志和报告只显示人数、话题数、状态，不输出用户名；
- 401/403、Cloudflare、Turnstile 或 CAPTCHA 被视为停止条件，不尝试绕过；
- 输出用户名只在本地用于随后调用公开收藏 API，`seed_users*.txt` 已被 Git 忽略。

安全边界参数：

```powershell
# 限制一次运行最多探测 50 个话题，适合首次验证
python tool\recommend_dataset\collect_user_seeds.py --config ... `
  --target-users 100 --max-topics 50

# 清空发现游标但保留已收集的本地种子
python tool\recommend_dataset\collect_user_seeds.py --config ... --reset-progress
```

社区作者样本天然偏向活跃用户，不能代表 Bangumi 全体用户。模型报告必须继续保留
`seed_users`、评测用户数与冷启动样本量；本地产生的稳定散列 ID 属于假名化标识，
不要将逐用户交互或原始用户名数据公开发布。

`dataset_config.eval2025.json` 的旧字段 `max_pages_per_type` 会兼容映射到 `max_pages_per_run=2`。
这表示每位尚未完成的用户每次运行最多请求 2 页，而不是最多保留 200 条；重复运行会继续抓取，
已有完整用户不会重复请求。无需 `--refetch` 即可补全历史；`--refetch` 仅用于主动从 offset=0 刷新。

## 交互引用补抓（--from-interactions）

交互表中引用了大量尚未采集的 subject_id（当前 dry-run 场景：2611 个引用中 2601 个缺失）。
补抓流程：

1. `referenced = interactions 去重 subject_id`；`existing = subjects 中 status=ok 的行`
2. `missing = referenced - subjects 表`；此外把 `status=pending/failed` 的已 claim 行重新加入队列，
   因此中断后不会漏抓，也不会重复插入
3. 排除 `known_subjects` 中已确认的非动画条目（非动画只记入 known_subjects，不写入动画表）
4. 逐个 `claim`（插入占位行）→ 抓取 → ok / permanent(404) / failed / non_anime
5. 默认 `--priority value` 先补 validation/test，再按 regular/strong 训练支持度排序；
   `--priority subject-id` 可恢复数字顺序
6. `--failed-only` 只重试 `status=failed` 且被交互引用的条目；`--limit N` 截断本轮；
   `--dry-run` 只打印统计不发请求

## 清洗后的模型视图

- `interactions.csv` 始终保留全部可审计证据，并增加 `collection_complete`、`feedback_tier`、
  `preference` 与 `confidence_weight`；用户名与 salt 从不导出。
- `complete_only=true` 时，训练/验证/测试文件只保留已确认采集完整的用户。
- `strong_positive`：显式评分 7～10；`regular_positive`：未达强反馈的 collect/doing；
  `weak_positive`：wish/on_hold；`negative`：dropped 或评分 1～4。
- 原始正反馈视图保留为 `*_interactions.csv`；另输出 `*_strong_interactions.csv`、
  `*_regular_interactions.csv` 和 `*_core_interactions.csv`。
- core 默认要求用户在训练期至少 `min_positive_interactions` 条 regular/strong 反馈，且条目训练支持度
  至少 `core_min_item_support`；阈值写入 `dataset_report.json`，便于做消融而不是暗中删数据。
- `max_train_interactions_per_user=N` 可构建用户平衡视图：只在当前训练时间窗内保留每人最近 N 条，
  validation/test 不裁剪；rolling CV 会在每一折重新裁剪，因此不会用未来交互决定早期训练样本。

## 严格时间切分（updated_at 驱动，UTC）

训练窗口 `train_end = train_end_date 23:59:59 UTC`（默认 2025-12-31）；
validation = 之后一个自然季度；test = 再一个季度。**交互切分主要由 updated_at 决定**：

| updated_at（转 UTC 后） | 归属 |
|---|---|
| ≤ train_end | train |
| 在 validation 季度 | validation |
| 在 test 季度 | test |
| 缺失 / 无法解析 / naive（无时区） | unassigned（不进任何训练/评测文件） |
| 晚于 test 窗口 | future（不进任何文件） |
| 早于条目 air_date | invalid_temporal（不进任何文件） |

时区规则：正确解析 `Z` 与 `+08:00` 等 ISO-8601 offset 并统一转 UTC 比较；
**naive datetime 一律拒绝**（不允许 naive 与 aware 混用导致静默泄漏）。
条目 air_date 缺失 → 标记 `unknown_air_date`，不得进入严格冷启动评测，不得静默视为训练条目。

条目标记：

- `warm_item`：训练集 ≥1 个正交互
- `few_shot_item`：训练集正交互 1～20
- `train_zero_interaction`：train_end 前已播出但训练集无正交互
- `cold_item`：**训练集零交互**且在 validation/test 出现正交互（仅在验证季度播出不算 cold）
- `new_release`：air_date 落在 validation/test 季度
- `strict_cold_new_release`：同时满足 cold_item 与 new_release

## 信息泄漏说明（重要）

- 严格模式（`evaluation.strict_temporal: true`，默认）下，TF-IDF 内容模型**只使用静态/近似静态字段**：
  tags、meta_tags、platform、episode_count 分桶、production/director/series_composer/original_work/music、
  voice_actors、前作/续作关系、summary、year/season（类别化编码）。
- **默认禁止使用**：score、rank、rating_total、collection_total、wish/doing/collect/on_hold/dropped 计数——
  这些是抓取时刻的全量统计快照，可能包含验证/测试期之后的信息。
- 若显式打开 `allow_dynamic_popularity_features: true`，报告会标记 `potential_feature_leakage: true`。
- 当前 subjects 元数据并非历史快照，因此标签、简介、制作信息也无法保证完全是当时状态——
  严格模式只排除明显的动态统计。这是 snapshot 数据集的已知限制。
- popularity_baseline 只使用**训练期**交互计数，绝不使用验证/测试计数。

## TF-IDF 内容推荐基线

- 稀疏矩阵：分类特征用 `MultiLabelBinarizer`（命名空间 token，如 `tag:治愈`、`staff:京都动画`、
  `director:山田尚子`、`actor:早见沙织`），summary 用 `TfidfVectorizer(analyzer="char",
  ngram_range=(2,4), min_df=2)`（中文不做英文式空格分词），合并后 L2 normalize。
  **不构建稠密 item×item 相似矩阵。**
- 特征组权重（`content_model.feature_weights`）：tags 1.0 / staff 0.8 / summary 0.5 /
  voice_actors 0.3 / context 0.2。
- 用户画像（仅训练窗口正反馈）：`user = positive_centroid − λ × negative_centroid`，
  λ 默认 0.2（dropped/1～4 分交互的 negative_weight 参与负质心），最终 L2 normalize。
- 候选集：air_date ≤ 评测窗口末、排除 nsfw、仅动画；每个用户只排除自己的历史交互，
  不得把所有用户看过的条目做全局排除。
- 评测：Precision/Recall/F1/NDCG@5/10/20、HitRate@10、MRR@20、Catalog Coverage@20，
  按用户平均，二元 relevance，同分按 subject_id 稳定排序，随机操作固定 seed=42。
  分组：`validation_all/cold_item/strict_cold_new_release`、`test_all/cold_item/strict_cold_new_release`、
  `test_incremental`（画像用 train+validation，绝不用 test）。
- 数据不足（无可评估用户/无正样本/窗口为空）→ `status="insufficient_data"`，记录
  users/positives/candidate_items，**不报 0 分冒充有效结果**。
- 不报告普通分类 Accuracy：未观察到的 user×item 不是已确认负样本，在高度稀疏的推荐矩阵中把它们
  当 true negative 会得到接近 100% 但毫无意义的“准确率”；使用 Precision/Recall/F1/NDCG 等 Top-K 指标。
- 产物：`data/baseline/feature_matrix.npz`、`subject_ids.npy`、`model_meta.json`、`baseline_report.json`。

## 第一版 Implicit ALS

- 固定 `factors=64`、`regularization=0.05`、`alpha=2.0`、`iterations=20`、seed=42；
- Train 上比较只用正反馈与 `negative_scale=0.25` 两个固定变体，只按 Validation NDCG@10 选择；
- 选择后用 Train+Validation 重训，Test 只在选型完成后评测；
- 交互目录候选 = 历史中已经出现的条目 + 截止窗口已播出的内容条目；逐用户排除自己的历史；
- 另报告内容目录结果，便于和 TF-IDF 在同一条目范围对照；
- 产物：`data/als/model.npz`、`user_ids.npy`、`subject_ids.npy`、`model_meta.json`、`als_report.json`。

`run_als_cv.py` 默认使用 2025-06-30、2025-09-30、2025-12-31 三个 rolling-origin
训练截止点，每折只验证紧随其后的自然季度，按各折 Validation NDCG@10 均值选参数并报告标准差；
测试窗口完全不参与交叉验证。core 的用户数和条目支持度阈值在每一折训练窗内重新计算，
不会用后续季度的信息反向筛选早期训练样本。

2026-08-09 第一版结果：Validation 上正反馈变体 NDCG@10 为 0.052527，略高于负反馈
变体的 0.052485，故选择正反馈。Test 全交互目录（21530 候选）ALS NDCG@10=0.065995，
高于 Popularity 的 0.048800；Recall@20=0.042355，低于 Popularity 的 0.049053。
ALS 对训练期零交互的冷条目得分为零，这是后续与内容模型融合要解决的核心问题。

### 扩展版与时间衰减

扩展采集把有效交互用户从 576 扩到 770，原始交互从 207005 扩到 366820；但直接把更多历史
交互喂给原参数模型，在相同 438 名旧用户、相同相关项和相同候选目录上反而令 NDCG@10 从
0.083908 降到 0.058813。分布审计发现扩展后旧用户训练历史中位数从 132 增至 359.5，且包含
大量多年以前的口味；问题不是“数据越多越差”，而是旧行为与新行为被赋予了相同置信度。

因此置信矩阵支持按交互时间进行指数衰减：`weight = 0.5 ** (age_days / half_life_days)`。
rolling-origin CV 在每折只使用该折训练截止点计算年龄，缺失时间不衰减，避免未来信息泄漏。
三个历史季度的 mean Validation NDCG@10：不衰减 0.070168，365 天 0.081370，730 天
0.075471，1460 天 0.072161，2920 天 0.071095。固定 365 天后，`regularization=0.1`；继续固定
该值后，32/64/96 因子的结果分别为 0.084131/0.081649/0.073593，最终冻结 32 因子。

冻结候选 `dataset_config.expand_recency_v1.json` 的 Test 全交互目录结果为：Precision@10
0.073504、Recall@20 0.059712、F1@20 0.047842、NDCG@10 0.086322。公平同人群比较中，
相对旧模型 NDCG@10 提升 2.95%，Recall@20 提升 11.04%，F1@20 提升 7.89%；Precision@10
下降 3.05%，Catalog Coverage 从 0.068581 降至 0.056686。故保留该候选，但多样性下降和
训练期零交互冷条目仍是已知问题。该 Test 已用于本轮最终诊断，后续调参必须换新的时间窗口，
不能继续用它选型。

## 分层训练准入门槛（check_dataset.py）

默认检查纯 ALS：缺少条目内容元数据不会阻止矩阵分解，因为 ALS 只需要用户—条目交互。

| 检查项 | 阈值 |
|---|---|
| valid_users | ≥ 500 |
| positive_train_interactions | ≥ 50000 |
| validation / test interactions | > 0 |
| temporal leakage rows | == 0 |

混合模型另加 `--require-hybrid`，要求具有内容元数据的 validation/test 冷条目分别 ≥ 100。
`subject_reference_coverage` 的目标 0.98 继续报告，但仅作为历史长尾丰富度提示；在线混合推荐
可对 warm item 使用 ALS，对当前新番按需抓取内容元数据，因此不要求补齐全部历史条目。

退出码：`0` 所选层级通过；`2` 数据结构有效但未达阈值；`1` 报告损坏、缺失或逻辑错误。
`dataset_report.json.readiness` 分别给出 `ready_for_als`、`ready_for_hybrid` 及 blockers。

2026-08-09 的本地研究快照：576 个有效用户、125186 条训练正反馈、validation 13884、
test 14806、时间泄漏 0；内容冷条目 validation 192 / test 227。纯 ALS 与混合训练准入均通过。

## 字段命名规范

交互表与所有导出文件统一使用 **`anon_user_id`**（旧文档中的 `anonymous_user_id`
是早期笔误，不构成字段名）。假名化 ID = SHA-256(salt + username)，salt 只存本地
`data/salt.txt`（gitignore），任何导出不含用户名与 salt。原始种子文件和 checkpoint DB 的
`seed_users` 表为断点续跑在本地保留用户名，均被 Git 忽略，不属于导出数据集。

## 隐私与合规

- 交互只存 `anon_user_id`；收藏接口响应中的评论、用户标签、隐私标记、进度等个人字段
  在模型层直接丢弃；不采集头像、签名、好友关系、IP；不抓 HTML；不绕过任何验证。
- **抽样偏差**：OpenAPI 没有用户枚举接口；阶段 2 从公开社区话题作者发现种子，仍是
  非随机抽样，明显偏向活跃或资深用户。
- 补抓只处理交互表中已出现的 subject_id，不猜测、不反向枚举用户。

## 配置迁移（阶段 1 → 阶段 1.5）

将 `dataset_config.json` 更新为示例配置 `dataset_config.example.json` 的结构：

```json
{
  "splits": { "train_end_date": "2025-12-31" },
  "evaluation": {
    "strict_temporal": true,
    "allow_dynamic_popularity_features": false,
    "top_k": [5, 10, 20],
    "negative_profile_weight": 0.2,
    "random_seed": 42
  },
  "content_model": {
    "summary_analyzer": "char",
    "summary_ngram_min": 2,
    "summary_ngram_max": 4,
    "summary_min_df": 2,
    "feature_weights": { "tags": 1.0, "staff": 0.8, "summary": 0.5, "voice_actors": 0.3, "context": 0.2 }
  }
}
```

即：`splits.train_end_date` 改为 `2025-12-31`，并新增 `evaluation` 与 `content_model` 两节
（缺省时程序使用与示例相同的默认值，旧配置可无痛运行）。

## 已知限制（如实声明）

1. **用户侧抽样偏差**：OpenAPI 无用户枚举入口，社区作者种子偏向活跃用户。
2. **条目覆盖**：无全量列举接口，按日历+季度搜索+交互引用补抓，历史条目无法保证 100% 覆盖。
3. **快照非历史**：评分/收藏计数为抓取时刻值，严格模式不把它们用于内容模型。
4. **私密/空收藏**：如实记录为 empty/unavailable，不伪造。
5. **U+2028/U+2029**：条目简介可能包含行分隔符字符；导出时已转义，任何按行读取的
   解析器都应使用文件迭代器而非 `str.splitlines()`。
