# 工作区交付清单（2026-09-24 起始快照）

本清单用于组织已有改动的审阅和提交，不代表下列内容已提交、发布或完成设备验收。起始 HEAD：`400040469ae1819034e4cf459bd5c8daf75b5b84`。100 个已跟踪修改、6 个删除、130 个未跟踪文件，共 236 个路径；未跟踪目录已展开为文件。

原始路径/状态/哈希保存在被忽略的 `.dart_tool/maintenance-followup-20260924/baseline.json`。本清单不包含凭据值、运行数据库、WebView 用户目录、模型或发布符号。

## 审阅与提交顺序

先审阅维护基础设施，再处理账号基础、社区/私信与恢复，随后交付更新器、展示、打印工坊和官网。每组先做对应回归，集成后运行 Full；每个实际提交都应能独立分析和测试。分组是审阅边界，不是可以直接执行的自动暂存列表。

共享文件必须按代码块审阅：`tool/build_release.ps1` / `tool/tests/release_build_test.ps1` 同时涉及发布追溯和镜像参数；`CommunityService` 同时含账号守卫与小组逻辑；`pubspec.*`、README、文档索引应随功能更新。不要对这些路径直接执行一揽子暂存。

本轮新增的社区/发现页职责拆分和 Windows 冒烟入口作为后续维护提交，依赖对应功能基线；不要将移出的代码误判为原功能删除。详见 [本轮实施说明](FOLLOWUP_2026-09-24.md)。

| 组 | 起始路径数 | 交付边界 | 验证 |
| --- | ---: | --- | --- |
| 维护基础设施 | 36 | 先提交工具版本、环境准备、统一验证、诊断与发布防护，锁文件跟随输入依赖一起审阅。 | toolchain / architecture / tools / privacy 回归 |
| 账号与会话 | 33 | 以账号归属、登录恢复、Cookie/浏览器身份及诊断为一个行为集合；不要拆掉配套迟到响应测试。 | account / website / login / session 测试 |
| 社区与好友 | 33 | 依赖账号基础设施；P1 写策略、私密小组回退与提交回执一起审阅。 | 各写动词账号切换、group/community/friends 回归 |
| 私信 | 25 | 依赖账号基础设施；收件箱、联系人、草稿及发送队列保持相同账号归属规则。 | pm_*，尤其 uncertain 不重放 |
| 本地数据恢复 | 12 | 按 RSS、收藏/同步、番键会开库恢复分别审阅，不更改既有本机数据。 | room_local_storage / rss / data_consistency / backup 回归 |
| 双源更新 | 18 | 客户端续传、原生安装路径、镜像发布脚本/工作流是同一交付主题；涉及原生变更须整包发布。 | 更新测试、mirror/release 脚本、Full 构建及安装验收 |
| 视觉与推荐展示 | 16 | 组件、推荐卡片与视觉证据一起审阅；不混入 Python 模型上线。 | 推荐反馈、手机可读性与布局回归 |
| 打印工坊 | 17 | 新功能、字体/OFL、PDF 依赖及锁文件一起交付；pubspec 位于共享集成组，需要选择相应代码块。 | tier_print_*，原生保存与实体尺寸仍需人工验收 |
| 官网 | 23 | 移除未用 D1 模板与依赖，同时保留归档；类型/SSR/静态导出/浏览器测试一起提交。 | npm check / audit / Playwright |
| 共享集成 | 5 | README 分别摘取对应主题；pubspec 与锁文件关联打印工坊；页面入口随各功能审阅。不能只根据文件名整文件归并。 | 所有受影响模块回归与 Full |
| 共享文档 | 18 | 历史审查与证据保持原日期；当前状态通过实施记录说明。审阅截图是否仅为合成数据后再纳入提交。 | 文档链接、隐私检查、历史/当前状态一致性 |

## 逐路径清单

`M` 为已跟踪修改，`D` 为既有删除，`?` 为起始时未跟踪文件。本轮没有恢复这些既有删除，也没有将未跟踪文件自动提交。

### 维护基础设施

| 状态 | 路径 |
| --- | --- |
| `M` | `.github/workflows/flutter.yml` |
| `M` | `.github/workflows/repository-privacy.yml` |
| `M` | `.gitignore` |
| `M` | `analysis_options.yaml` |
| `M` | `native-android/README.md` |
| `M` | `tool/build_release.ps1` |
| `M` | `tool/package_windows_release.ps1` |
| `M` | `tool/recommend_dataset/requirements.txt` |
| `M` | `tool/semantic_retrieval/requirements.txt` |
| `M` | `tool/tests/release_build_test.ps1` |
| `?` | `.fvmrc` |
| `?` | `.github/CODEOWNERS` |
| `?` | `.github/dependabot.yml` |
| `?` | `.github/pull_request_template.md` |
| `?` | `.github/workflows/device-smoke.yml` |
| `?` | `.github/workflows/native-builds.yml` |
| `?` | `.github/workflows/python.yml` |
| `?` | `AGENTS.md` |
| `?` | `CONTRIBUTING.md` |
| `?` | `SECURITY.md` |
| `?` | `integration_test/platform_smoke_test.dart` |
| `?` | `integration_test/windows_webview_smoke_test.dart` |
| `?` | `tool/README.md` |
| `?` | `tool/check_toolchain.py` |
| `?` | `tool/lock_python.ps1` |
| `?` | `tool/maintenance/clean_workspace.ps1` |
| `?` | `tool/qa/acceptance.example.json` |
| `?` | `tool/recommend_dataset/requirements.in` |
| `?` | `tool/release_provenance.py` |
| `?` | `tool/semantic_retrieval/requirements.in` |
| `?` | `tool/setup_workspace.ps1` |
| `?` | `tool/tests/release_provenance_test.py` |
| `?` | `tool/tests/workspace_cleanup_test.ps1` |
| `?` | `tool/toolchain.json` |
| `?` | `tool/toolchain.ps1` |
| `?` | `tool/verify_all.ps1` |

### 账号与会话

| 状态 | 路径 |
| --- | --- |
| `M` | `lib/core/auth/website_cookie_bridge.dart` |
| `M` | `lib/core/auth/website_identity.dart` |
| `M` | `lib/core/auth/website_session.dart` |
| `M` | `lib/screens/account_status_screen.dart` |
| `M` | `lib/screens/auth_screen.dart` |
| `M` | `lib/screens/website_login_screen.dart` |
| `M` | `lib/state/account_access_controller.dart` |
| `M` | `lib/state/service_providers.dart` |
| `M` | `lib/state/session_controller.dart` |
| `M` | `lib/state/website_session_controller.dart` |
| `M` | `lib/widgets/oauth_authorization_dialog.dart` |
| `M` | `test/account_access_test.dart` |
| `M` | `test/session_controller_test.dart` |
| `M` | `test/website_login_screen_test.dart` |
| `M` | `test/website_session_controller_test.dart` |
| `?` | `docs/qa/COOKIE_COMMUNITY_AUDIT_2026-09-23.md` |
| `?` | `docs/qa/LOGIN_AND_DATA_FIXES_2026-09-22.md` |
| `?` | `docs/qa/LOGIN_REPAIR_ENTRY_2026-09-22.md` |
| `?` | `docs/qa/MOBILE_PM_RECOVERY_2026-09-21.md` |
| `?` | `docs/qa/WEBSITE_LOGIN_VERIFICATION_2026-09-21.md` |
| `?` | `docs/qa/WEBSITE_SESSION_REUSE_2026-09-19.md` |
| `?` | `lib/core/diagnostics/account_diagnostics.dart` |
| `?` | `lib/core/network/account_diagnostics_interceptor.dart` |
| `?` | `lib/state/account_diagnostics_provider.dart` |
| `?` | `lib/widgets/account_diagnostics_dialog.dart` |
| `?` | `test/account_diagnostics_dialog_test.dart` |
| `?` | `test/account_diagnostics_test.dart` |
| `?` | `test/login_recovery_regression_test.dart` |
| `?` | `test/website_browser_identity_test.dart` |
| `?` | `test/website_navigation_session_test.dart` |
| `?` | `test/website_operation_audit_test.dart` |
| `?` | `test/website_request_recovery_test.dart` |
| `?` | `test/website_session_recovery_test.dart` |

### 社区与好友

| 状态 | 路径 |
| --- | --- |
| `M` | `lib/core/network/community_p1_parser.dart` |
| `M` | `lib/core/network/community_service.dart` |
| `M` | `lib/models/community_models.dart` |
| `M` | `lib/screens/common_friends_page.dart` |
| `M` | `lib/screens/community_group_browse_screen.dart` |
| `M` | `lib/screens/community_group_screen.dart` |
| `M` | `lib/screens/community_hub_page.dart` |
| `M` | `lib/screens/community_page.dart` |
| `M` | `lib/screens/community_topic_screen.dart` |
| `M` | `lib/screens/friends_page.dart` |
| `M` | `lib/state/notify_controller.dart` |
| `M` | `lib/state/user_preferences_controller.dart` |
| `M` | `lib/widgets/community_composer.dart` |
| `M` | `lib/widgets/community_loading.dart` |
| `M` | `lib/widgets/community_widgets.dart` |
| `M` | `test/community_composer_test.dart` |
| `M` | `test/community_service_test.dart` |
| `?` | `docs/qa/BANGUMI_UPSTREAM_LOGIC_2026-09-22.md` |
| `?` | `docs/qa/COMMUNITY_VERIFICATION_LOOP_2026-09-21.md` |
| `?` | `docs/qa/GROUP_FEATURE_REVIEW_2026-09-22.md` |
| `?` | `docs/qa/GROUP_TOPIC_RECEIPTS_2026-09-22.md` |
| `?` | `docs/qa/MANAGED_GROUP_ROLE_FIXES_2026-09-22.md` |
| `?` | `lib/core/network/community_write_client.dart` |
| `?` | `lib/models/community_topic_submission.dart` |
| `?` | `test/community_account_retry_test.dart` |
| `?` | `test/community_session_audit_test.dart` |
| `?` | `test/friends_session_screen_test.dart` |
| `?` | `test/group_screen_state_test.dart` |
| `?` | `test/group_state_regression_test.dart` |
| `?` | `test/group_topic_composer_test.dart` |
| `?` | `test/group_topic_read_recovery_test.dart` |
| `?` | `test/group_topic_submission_test.dart` |
| `?` | `test/verification_loop_regression_test.dart` |

### 私信

| 状态 | 路径 |
| --- | --- |
| `M` | `lib/core/network/pm_html_parser.dart` |
| `M` | `lib/core/network/pm_service.dart` |
| `M` | `lib/core/storage/snapshot_cache.dart` |
| `M` | `lib/features/pm/presentation/pm_contacts_view.dart` |
| `M` | `lib/models/pm_models.dart` |
| `M` | `lib/screens/messages_page.dart` |
| `M` | `lib/screens/pm_page.dart` |
| `M` | `lib/state/pm_contacts_controller.dart` |
| `M` | `lib/state/pm_mailbox_controller.dart` |
| `M` | `lib/state/pm_send_queue_controller.dart` |
| `M` | `lib/widgets/pm_draft_editor.dart` |
| `M` | `test/pm_chat_layout_test.dart` |
| `M` | `test/pm_contacts_test.dart` |
| `M` | `test/pm_draft_owner_test.dart` |
| `M` | `test/pm_flow_safety_test.dart` |
| `M` | `test/pm_html_parser_test.dart` |
| `M` | `test/pm_mailbox_controller_test.dart` |
| `M` | `test/pm_page_test.dart` |
| `M` | `test/pm_send_queue_test.dart` |
| `M` | `test/pm_service_test.dart` |
| `M` | `test/snapshot_cache_test.dart` |
| `M` | `test/support/pm_fixtures.dart` |
| `?` | `test/pm_optimization_test.dart` |
| `?` | `test/pm_request_stability_test.dart` |
| `?` | `test/pm_session_state_audit_test.dart` |

### 本地数据恢复

| 状态 | 路径 |
| --- | --- |
| `M` | `lib/core/storage/rss_store.dart` |
| `M` | `lib/features/anime_appreciation/room_pages.dart` |
| `M` | `lib/features/anime_appreciation/room_storage.dart` |
| `M` | `lib/features/collection/application/collection_editor.dart` |
| `M` | `lib/features/sync/application/pending_sync_controller.dart` |
| `M` | `lib/state/rss_controller.dart` |
| `M` | `test/backup_runtime_test.dart` |
| `M` | `test/room_local_storage_test.dart` |
| `M` | `test/rss_controller_test.dart` |
| `?` | `docs/architecture/full-review-2026-09-22/room_open_repro_test.dart` |
| `?` | `test/concurrent_state_recovery_test.dart` |
| `?` | `test/data_consistency_regression_test.dart` |

### 双源更新

| 状态 | 路径 |
| --- | --- |
| `M` | `android/app/src/main/kotlin/com/wweiyi/mubangumi/UpdateInstaller.kt` |
| `M` | `android/app/src/main/res/xml/update_file_paths.xml` |
| `M` | `lib/core/update/app_update_service.dart` |
| `M` | `lib/core/update/github_release.dart` |
| `M` | `lib/core/update/update_download.dart` |
| `M` | `lib/widgets/github_release_dialog.dart` |
| `?` | `.github/workflows/gitee-mirror.yml` |
| `?` | `docs/GITEE_MIRROR.md` |
| `?` | `docs/qa/UPDATE_MIRROR_2026-09-21.md` |
| `?` | `lib/core/update/release_catalog.dart` |
| `?` | `lib/core/update/update_source.dart` |
| `?` | `test/release_catalog_test.dart` |
| `?` | `test/update_resume_test.dart` |
| `?` | `tool/mirror_release.py` |
| `?` | `tool/publish_gitee.ps1` |
| `?` | `tool/requirements-mirror.in` |
| `?` | `tool/requirements-mirror.txt` |
| `?` | `tool/tests/mirror_release_test.py` |

### 视觉与推荐展示

| 状态 | 路径 |
| --- | --- |
| `M` | `lib/screens/fan_recommend_page.dart` |
| `M` | `lib/widgets/ascii_refresh.dart` |
| `M` | `lib/widgets/subject_widgets.dart` |
| `M` | `test/layout_review_test.dart` |
| `M` | `test/recommendation_feedback_experience_test.dart` |
| `?` | `docs/qa/original-art-2026-09-19/README.md` |
| `?` | `docs/qa/original-art-2026-09-19/preview-dark-compact.png` |
| `?` | `docs/qa/original-art-2026-09-19/preview-dark.png` |
| `?` | `docs/qa/original-art-2026-09-19/preview-light-compact.png` |
| `?` | `docs/qa/original-art-2026-09-19/preview-light.png` |
| `?` | `docs/qa/original-art-2026-09-19/recommendation-phone-compact.png` |
| `?` | `docs/qa/original-art-2026-09-19/recommendation-phone-dark-compact.png` |
| `?` | `docs/qa/original-art-2026-09-19/recommendation-phone.png` |
| `?` | `lib/widgets/projection_art.dart` |
| `?` | `lib/widgets/recommendation_ticket.dart` |
| `?` | `test/projection_design_test.dart` |

### 打印工坊

| 状态 | 路径 |
| --- | --- |
| `?` | `assets/fonts/OFL.txt` |
| `?` | `assets/fonts/README.md` |
| `?` | `assets/fonts/TierPrintHangul-Regular.ttf` |
| `?` | `assets/fonts/TierPrintSans-Regular.ttf` |
| `?` | `lib/features/tier_print/tier_print_cancel.dart` |
| `?` | `lib/features/tier_print/tier_print_catalog.dart` |
| `?` | `lib/features/tier_print/tier_print_covers.dart` |
| `?` | `lib/features/tier_print/tier_print_models.dart` |
| `?` | `lib/features/tier_print/tier_print_page.dart` |
| `?` | `lib/features/tier_print/tier_print_pdf.dart` |
| `?` | `test/tier_print_catalog_test.dart` |
| `?` | `test/tier_print_covers_test.dart` |
| `?` | `test/tier_print_layout_test.dart` |
| `?` | `test/tier_print_page_test.dart` |
| `?` | `test/tier_print_pdf_test.dart` |
| `?` | `tool/qa/check_tier_print_pdf.py` |
| `?` | `tool/qa/tier_print_smoke.dart` |

### 官网

| 状态 | 路径 |
| --- | --- |
| `M` | `.github/workflows/pages.yml` |
| `M` | `website/.gitignore` |
| `M` | `website/README.md` |
| `M` | `website/app/ProductDemo.tsx` |
| `M` | `website/app/globals.css` |
| `M` | `website/app/page.tsx` |
| `D` | `website/db/index.ts` |
| `D` | `website/db/schema.ts` |
| `D` | `website/drizzle.config.ts` |
| `D` | `website/drizzle/meta/_journal.json` |
| `D` | `website/examples/d1/app/api/notes/route.ts` |
| `D` | `website/examples/d1/db/schema.ts` |
| `M` | `website/package-lock.json` |
| `M` | `website/package.json` |
| `M` | `website/tests/rendered-html.test.mjs` |
| `M` | `website/vite.config.ts` |
| `M` | `website/worker/index.ts` |
| `?` | `docs/archive/WEBSITE_D1_SCAFFOLD.md` |
| `?` | `website/.node-version` |
| `?` | `website/.npmrc` |
| `?` | `website/playwright.config.ts` |
| `?` | `website/tests/browser/homepage.spec.ts` |
| `?` | `website/tests/serve-static.mjs` |

### 共享集成

| 状态 | 路径 |
| --- | --- |
| `M` | `README.md` |
| `M` | `lib/screens/discover_page.dart` |
| `M` | `lib/screens/library_page.dart` |
| `M` | `pubspec.lock` |
| `M` | `pubspec.yaml` |

### 共享文档

| 状态 | 路径 |
| --- | --- |
| `?` | `docs/README.md` |
| `?` | `docs/architecture/PROJECT_MAINTENANCE_REVIEW_2026-09-22.md` |
| `?` | `docs/architecture/full-review-2026-09-22/account-retry-before.txt` |
| `?` | `docs/architecture/full-review-2026-09-22/checks.json` |
| `?` | `docs/architecture/full-review-2026-09-22/dart-outdated.json` |
| `?` | `docs/architecture/full-review-2026-09-22/inventory.json` |
| `?` | `docs/architecture/full-review-2026-09-22/npm-audit.json` |
| `?` | `docs/architecture/full-review-2026-09-22/room-open-repro.txt` |
| `?` | `docs/architecture/full-review-2026-09-22/website-types.txt` |
| `?` | `docs/maintenance/IMPLEMENTATION_2026-09-22.md` |
| `?` | `docs/qa/ANDROID_RELEASE_CHECKLIST.md` |
| `?` | `docs/qa/BUG_AUDIT_2026-09-22.md` |
| `?` | `docs/qa/PM_LOGIC_AUDIT_2026-09-22.md` |
| `?` | `docs/qa/PM_REQUEST_STABILITY_2026-09-21.md` |
| `?` | `docs/qa/TIER_PRINT_WORKSHOP.md` |
| `?` | `docs/qa/WORKSPACE_CLEANUP_2026-09-19.md` |
| `?` | `docs/qa/bug-audit-2026-09-22/repro.txt` |
| `?` | `docs/qa/bug-audit-2026-09-22/repro_test.dart` |
