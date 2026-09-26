# AstroBox Creator Console（ABCC）功能盘点与 OronBox 对齐参考

> 盘点日期：2026-09-14  
> 代码来源：`/Users/orpudding/Documents/GitHub/AstroBoxCreatorConsole`  
> 目的：完整了解 ABCC 的产品边界、实现方式、数据契约与交互模式，为 OronBox 后续对齐提供可核查的清单。本文件是代码阅读报告，不是对 ABCC 行为的臆测。

## 结论摘要

ABCC 不是单纯的 AstroBox 资源上传器，而是一套围绕 AstroBox 生态的创作者与运营控制台：资源发布、GitHub 仓库协作、资源加密与授权交付、订单/SKU/CDK 管理、创作者分析、社区互动、爱发电运营、账号与权限、PR 审核、探索页维护、云控/推流、热更新和桌面端更新都在同一个应用内。

最值得 OronBox 对齐的几个原则是：

1. 资源的编辑态、构建态、发布态分层；manifest 是跨平台发布的中心契约，但每个外部平台仍有自己的适配器。
2. 包体分析、版本读取、身份读取、表盘 ID 修复、加密和 hash 都有独立逻辑模块；页面只负责编排和展示状态。
3. 正式发布以 GitHub 分支/提交/PR 为工作流核心，支持恢复草稿、继续处理中 PR、审核反馈和再提交。
4. 服务端 API 负责鉴权、token 刷新、订单/权益、分析和运营数据；前端用 React Query/本地状态组织加载、缓存和 mutation。
5. 外部数据源有明确的 fallback 和缓存策略：设备列表优先 CDN/raw，再 Contents API；更新检查失败静默处理；不能把“上游不存在”误当成“可发布”。
6. 管理能力强调预览、显式确认、可撤销状态（启用/停用、撤销 release、关闭/重开举报）和审计上下文。

## 1. 应用结构与导航

入口和路由集中在 `app/main.tsx`，导航定义在 `app/layout/nav-config.ts`。主要用户可见页面如下：

| 区域 | 路由/页面 | 主要能力 |
|---|---|---|
| 首页 | `/` | 创作者概览、下载统计、热门下载、设备分布、爱发电收入概览 |
| 数据 | `/analysis` | 区域热力图、周期筛选、下载趋势、评分分布、资源明细 |
| 互动 | `/interactions` | 创作者评论列表、摘要、回复/互动处理 |
| 爱发电 | `/afdian-income`、`/afdian-messages` | 收入/订单/赞助者、私信会话、消息详情与发送 |
| 资源 | `/new-resource`、`/publish/edit`、`/manage`、`/publish` | 新建/编辑、已发布资源、审核队列、PR 状态和拒绝原因 |
| 加密 | `/encrypt` | 资源加密、加密文件键、付费平台配置、订单补发、CDK |
| 壁纸 | `/publish/wallpaper` | 壁纸工程/JSON 树/画布编辑器 |
| 账户 | `/profile`、`/login`、`/settings` | AstroBox/GitHub/爱发电登录、个人资料、偏好和更新开关 |
| 内部工具 | `/resreview`、`/cloudcontrol`、`/explorepage` | PR 审核、云控/资源推流、探索页 JSON/博客维护 |
| 管理后台 | `/admin/accounts`、`orders`、`reports`、`inbox`、`account-deletion`、`hotupdate` | 账号、订单权益、举报、信箱、注销工单、热更新 |

导航项可声明 `requireRoles`；当前 admin/moderator 可见账号、订单、举报、信箱、注销工单，只有 admin 可见热更新。桌面/移动 Tauri 壳和纯浏览器运行时共用前端路由，但文件读取、加密等能力会检查运行环境。

## 2. 资源发布工作流

### 2.1 发布表单分区

资源发布编辑页 `app/routes/resource/publish/new.tsx` 是编排层，拆成以下组件：

- `BasicInfoSection`：资源类型（`quick_app`、`watchface`、`canopus`）、名称、资源 ID/包名。表盘 ID 支持规范化输入和生成。
- `MediaSection`：封面、图标、多张预览图；预览图可重排、删除、查看和处理尺寸/压缩状态。
- `AuthorsLinksSection`：作者列表、是否绑定 AstroBox 账号、外部链接及图标选择。
- `DownloadsSection`：设备下载行、正式/试用下载、包体版本读取、版本号/`versionCode`、更新日志、重复设备校验。
- `ExtSection`：捆绑资源与插件，支持 required/recommend 两种模式，从资源目录和插件 index 选择。
- `EncryptConfigDialog`：按设备/文件配置上传加密。
- `RepoStepSection`：GitHub 仓库创建/选择与资源写入。
- `PrStepSection`：提交 PR、显示提交/审核状态。
- `VersionEditorDialog`：包体版本不能读取或版本未递增时的显式编辑/确认。

页面有自动保存草稿、发现未保存草稿时恢复/丢弃的对话框、版本号缺失/未递增的警告对话框；每个重要字段变化和发布阶段均写入 publish-flow 日志。

### 2.2 文件选择与移动端约束

`app/logic/publish/file-picker.ts` 的 `pickFiles()` 是统一入口。Tauri 环境使用原生 dialog + fs 读取后构造浏览器 `File`；浏览器环境才回退 HTML file input。原因是 Android/iOS WebView 的 `content://` 文件不能可靠地由 `FileReader`/`arrayBuffer()` 读取。任何新的上传 UX 都应遵守这个边界。

### 2.3 草稿与恢复

`publish-drafts.ts` 使用 IndexedDB 保存草稿、自动保存数据和文件元信息；`resources.ts` 可从 GitHub PR、旧版资源和 staging 资源重建编辑上下文。恢复不是单纯恢复 UI，而是重新建立资源、媒体、下载行、版本和 PR 状态，因此 OronBox 需要为“历史数据兼容”保留提交前复核。

## 3. 包体识别、版本和身份

### 3.1 版本/身份分析

`app/logic/publish/package-version.ts` 是通用包体分析器，支持：

- 小米 `.bin`/`.face`：固定偏移读取三字节版本；固定偏移读取 12 位表盘 ID。
- 小米 `.mwz`：解压 zip，定位内部 `.bin`，读/写内部包体。
- rpk/zip：读取 `manifest.json`，支持 `versionName`/`versionCode`、小米 `manifest-watch.json`。
- Vivo 表盘：从 zip manifest/router watchfaces 读取 dial id。

统一结果包含 `version`、`versionCode`、`identity`、`identityKind`、来源、是否可读/可写、失败原因和内部条目路径。`identityKind` 明确区分 package、watchface-id、dial-id。页面不应自行重复解析包名或表盘 ID。

### 3.2 表盘 ID 修复

`app/logic/publish/watchface-id.ts` 提供 12 位纯数字、`9798` 前缀校验、生成、已有目录 ID 查询和文件/`.mwz` 内部包体改写。写入前校验，改写后应重新分析并使用新文件/hash，避免只改显示值。

### 3.3 版本 UX

下载行会优先以包体内部版本为准并锁定；如果读取失败，允许显式编辑。已有资源更新时比较 `versionCode`，小于等于上一版本会阻止提交；相同文件 ID 的多个设备行可同步版本编辑结果。UX 上将“自动读取/锁定”“手动编辑”“未递增阻断”分开呈现。

## 4. manifest 与发布产物

### 4.1 ABCC manifest builder

`app/logic/publish/manifest.ts` 构建资源仓库的 manifest 和待上传文件清单。核心字段包括：

- `item`：资源 ID、名称、描述、类型、作者、预览/图标/封面引用。
- `links`：`{ icon, title, url }[]`。
- `downloads`：设备 token → `{ version, file_name, versionCode?, updatelogs? }`。
- `ext`：创作者特性开关、试用下载、捆绑资源、壁纸生成器配置等。

构建结果同时返回 manifest JSON、各类媒体、正式下载、试用下载、壁纸配置和资产路径。重复媒体可复用，路径可按平台后缀处理。`manifest-loader.ts` 负责从远端仓库加载并解析现有 manifest。

### 4.2 捆绑资源与插件

`bundledResources` 是结构化依赖关系：资源项有 id/name，插件项使用插件仓库 index 中的名称；required/recommend 去重，编辑器从资源目录或插件 index 拉取候选并允许切换模式。OronBox 对齐时应保留“依赖类型、必需/推荐、去重、可预览”四个维度。

### 4.3 外部发布适配

ABCC 自己的资源仓库 manifest 是内部契约；外部平台不能假设会原样消费它。尤其 AstroBox 的 `manifest_v2.json` 使用顶层 `links[]` 和 `downloads` 设备键，米坛则需要把链接/说明转换为正文字段。OronBox 应由服务端 publisher 为每个平台单独构造最终产物，并确保重试不会重复插入正文。

## 5. GitHub 与 PR 协作

`github-actions.ts` 是较完整的 GitHub 客户端层：

- GitHub API 代理、鉴权 token、超时、限流识别和重试。
- 创建用户仓库、等待初始 commit、确保资源分支。
- 读取当前用户仓库并支持名称搜索/下拉选择。
- 创建 blob/tree/commit/ref，批量写入二进制和文本。
- 设置仓库 topic/homepage。
- 创建和查询 Pull Request。

`fork.ts`、`branch.ts`、`submission.ts`、`staging-submission.ts` 将发布拆成 fork/分支、提交、staging 和 PR 阶段；`resources.ts` 从 PR 文件变更、catalog CSV patch、评论/审核记录恢复“正在处理的资源”。PR 被拒绝时列表页可打开拒绝原因，修复后重新提交。

重要 UX：仓库名输入支持已有仓库联想；上传/提交过程有阶段状态；失败信息包含 GitHub/服务端真实上下文；编辑器可恢复未完成发布，而不是要求用户从头填写。

## 6. 校验与规则审核

`validation.ts` 集中处理发布前校验：链接格式和必填字段、封面比例/大小、至少一个正式下载设备、正式/试用下载行、URL 不安全文件名等；返回总体 errors 和逐链接 errors。`rule-checks.ts` 是资源审核页的规则检查集合，可检查 manifest、文件、图像和元数据，并在 PR review 中按规则展示。

OronBox 对齐建议：将上传 gate、表单校验、服务端最终校验分成三层；错误应绑定资源/文件/设备行，避免只在提交按钮处给一个不可定位的总错误。

## 7. 设备目录与上游数据

`app/logic/devices/catalog.ts` 从配置的资源仓库读取 `devices_v2.json`，优先 jsDelivr 多域名、GitHub raw、代理镜像，全部失败后回退 GitHub Contents API；结果按 canonical id 去重，同时保留型号 alias。`loadDeviceTokenResolver()` 将型号号和 canonical id 都解析成 canonical id，供 manifest downloads 使用。

当前 ABCC 的设备源结构是 `vendor -> modelNumber -> { id, name }`；实际 AstroBox 上游还可能包含 `description`、`chip`、`fetch` 等字段。ABCC 的客户端将设备型号号和 canonical ID 统一解析，说明服务端/发布器不应仅依赖本地显示名。

对 OronBox 的明确建议：设备正式目录应由 OronBox Server 持有；AstroBox Repo 的 `devices_v2.json` 是 AstroBox 能力的上游参考；管理后台做纯增量 diff、逐项勾选、确认应用，不覆写未勾选项；上游删除先标记停用建议，不自动删除；客户端只读服务端，离线时才 fallback 本地。8 Pro、Watch S1 Pro 等不支持设备应从 AstroBox manifest 的 `downloads` 声明中静默过滤，不能阻止米坛或 OronBox 保存。

## 8. 加密、授权和商业交付

### 8.1 本地加密

`encryption.ts` 在 Tauri 环境调用 Rust `encrypt_aes_256_ecb`，随机生成 256-bit key，返回加密文件、SHA-256 hash 和 base64 key。浏览器环境明确拒绝 AES 加密。Rust 侧还提供日志、归档、GitHub 代理、AI 和爱发电等命令。

### 8.2 加密管理页

`/encrypt` 把加密文件、资源、设备、hash/key、付费平台配置放在一个工作台；支持爱发电和 CDK 两类 commerce platform。服务端 API 支持：平台配置增删、资源商品/SKU 映射、加密文件键查询/删除、CDK 批量生成/列表、爱发电订单 reconcile/reissue。

对应 UX 是“先查看当前配置 → 按资源/平台/设备编辑 → 明确删除确认 → 订单异常时 reconcile/补发”，而不是把 key 直接散落在资源表单中。

## 9. 订单、权益与后台运营

`app/api/astrobox/admin.ts` 和 `/admin/orders` 覆盖：

- 用户与角色详情、封禁信息、VIP 订单和角色授予。
- 公共订单、资源权益、资源 commerce 配置。
- 爱发电/CDK 来源区分。
- SKU/product/device 级映射和加密文件 key。
- 列表筛选、详情 dialog、手动覆盖/授予、删除确认。

后台页面不是只读报表，而是带 mutation 的运营控制面板。高风险动作都在 dialog 中展示目标详情后确认，并在 UI 中反馈结果。

## 10. 分析、社区和消息

### 数据分析

`analysis.ts` 和 `dashboard.ts` API 分开提供首页摘要与详细分析：7d/30d/90d/all 周期、china/world 地图范围、热力点/摘要、每日下载、评分分布、资源排行和趋势方向。页面在数据暂不可用时显示专门空状态，而不是假装 0。

### 评论互动

`interactions.ts` 提供创作者评论分页和总览；`community.ts` 提供评论详情（含 medal 等展示字段）。互动页按资源聚合、显示回复目标和摘要，适合对齐“待处理/已处理/资源上下文”UX。

### Inbox

`inbox.ts` 提供列表、未读计数、标记全读、单条删除；桌面端 `InboxDrawer`/`InboxBell` 在全局导航中提供未读入口。后台 `/admin/inbox` 可发送、查看最近消息和批量删除。前台消息通知和后台管理是两套视图，共用服务端状态。

## 11. 爱发电集成与 AI

`afdian-account.ts` 支持原生登录能力探测、密码登录、手机验证码登录、验证码刷新、登出、收入概览；`afdian.ts` 负责订单拉取/签名和 SKU 过滤；`afdian-management.ts` 支持管理概览、收入统计、收款订单、赞助者分页；`afdian-messages.ts` 支持会话、消息、用户详情和发送。

`ai.ts` 支持 AI API key 状态、保存/删除 key、通用 HTTP 请求和文档检索；Rust `ai.rs` 负责部分原生能力。`AfdianAiAutoReplyHost`、回复活动状态和卡片组件把 AI 自动回复作为可开关的辅助能力，不应默认替代人工发送。

## 12. 热更新与桌面更新

### 管理热更新

`/admin/hotupdate` 支持 release 和 eval patch 两类对象，平台覆盖 all/ios/android/macos/windows/linux。release 包含 channel、版本号/semver、原生版本范围、文件 sha256/size、文件基址、rollout、notes、enabled/revoked；patch 包含 channel、patchId、脚本、原生版本范围、enabled。API 提供创建、更新、删除、列表、签名 key 状态和 manifest/envelope preview。

页面有筛选、发布新版本、版本列表、补丁列表、下发预览；签名状态与公钥信息显式展示。对齐时应保留“生成物 hash + 签名预览 + 灰度比例 + 撤销”四个安全闸门。

### 客户端更新

`update-checker.ts` 从 GitHub releases/latest 获取正式 release，比较点分数字版本；网络失败不打扰用户。localStorage 保存忽略的 tag 和自动检查开关；`AutoUpdateChecker` 与 `UpdateAvailableDialog` 负责自动检查和“忽略此版本/禁用自动检查”等 UX。浏览器直开时更新检查不可用。

## 13. 壁纸编辑器

壁纸能力不是发布表单的一个文本字段，而是一套独立模型：

- `json-tree.ts`：解析、遍历和修改 JSON 树。
- `CanvasStage.tsx`：画布预览。
- `Inspector.tsx`、`Sidebar.tsx`、数值拖拽输入、颜色/透明度控件：可视化编辑。
- `editor-history.ts`：撤销/重做历史。
- `wizard-session.ts`：向导会话/恢复。
- `load-resources.ts`、`presets.ts`：资源加载和预设。
- `ErrorBoundary.tsx`：编辑器局部故障隔离。

对齐重点是“可视化编辑 + JSON 源码 + 历史记录 + 错误隔离”四层并存。

## 14. 账号、鉴权、权限和设置

`request.ts` 统一 axios 客户端、access/refresh token、401 自动刷新队列、用户封禁错误识别、超时和服务端错误提取；并避免显式 token 请求被错误自动续期。`account/store.ts` 用响应式外部状态维护当前账号；支持 AstroBox 原生认证、GitHub 登录状态、权限/角色和爱发电会话。

登录方式/环境由 `config/loginMethod.ts`、`nativeAuth.ts`、`casdoor.ts`、`repoEnv.ts` 等配置集中管理。设置页还承载 UI 缩放、通知、自动更新、AI/爱发电开关等偏好。对齐时应统一处理“登录中、token 刷新、被封禁、权限不足、网络失败、注销中”状态，不能只处理成功路径。

## 15. 日志、诊断和隐私

前端 `logic/logging` 有核心 logger、字段脱敏、反馈和 publish-flow session；Tauri Rust 侧有按日切割、敏感信息脱敏、资源发布会话日志、tar.gz 日志归档和分享命令。发布流程中的作者、链接、下载、版本、加密、提交阶段都有结构化事件。

这套诊断能力对 OronBox 很重要：用户遇到“上传成功但外部平台不对”时，需要能回溯分析结果、设备解析、manifest 构建、publisher 请求和服务端响应；日志导出还应主动遮蔽 token/key。

## 16. ABCC 对齐优先级

### P0：契约正确性

- 统一资源识别器结果：空 ID、默认快应用包名、表盘全零 ID 必须在上传 gate 处理；修复后重新写入文件、重新分析、重新 hash。
- AstroBox manifest 使用真实顶层 `links[]` 和 `downloads` 设备键；不支持设备不伪造 ID。
- 米坛发布器将附加链接插入正文开头，且重试幂等。
- 服务端承担设备目录，以上游 AstroBox `devices_v2.json` 为参考；后台做可审阅增量同步。

### P1：发布体验

- 草稿自动保存/恢复、PR 继续编辑、阶段进度和可定位错误。
- 包体版本自动读取、编辑、递增检查；表盘 ID 全零可在对话框输入合法新 ID并应用到文件。
- 外部平台预览：显示哪些设备会进入 AstroBox、哪些会被静默跳过及原因。

### P2：生态运营

- 加密资源、平台商品/SKU、CDK、订单 reconcile/reissue。
- 分析、互动、inbox、爱发电管理和 AI 辅助。
- 管理员账号/举报/注销/热更新控制面板。

### P3：工程质量

- token 刷新队列、服务端真实错误、重试/限流、上游数据缓存和多源 fallback。
- 结构化发布日志、脱敏、可导出诊断包。
- 对壁纸编辑器和资源发布使用相同的会话恢复/错误隔离思路。

## 17. 尚需对 ABCC 进一步核对的内容

本报告已覆盖仓库中所有前端路由、API 模块、发布逻辑、设备逻辑、Tauri 命令和主要可复用组件的职责。若要做“逐功能协议级对齐”，下一阶段应继续逐项导出并与 OronBox Server 对照：

- AstroBox 服务端每个 endpoint 的请求/响应字段、错误码和权限角色。
- ABCC 与 AstroBox Repo 实际发布资源的完整 `manifest_v2.json` 样本及目录布局。
- 资源更新、试用下载、捆绑资源、插件 index 的兼容版本策略。
- 热更新 envelope 签名算法、密钥轮换和客户端验签链路。
- 爱发电订单签名、补发幂等键和 CDK 消费状态转移。
- PR 审核规则的全部规则 ID、自动检查与人工 review 的边界。
- 壁纸编辑器 JSON schema、可视化属性映射和导出格式。

这些是可执行的下一轮对齐任务，不应在没有样本/服务端实现证据时凭字段名推导。
