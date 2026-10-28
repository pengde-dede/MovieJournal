# 观影记录 · MovieJournal

macOS 原生观影记录应用。使用 SwiftUI + SwiftData，最低 macOS 14，无第三方依赖，数据保存在本机。

## 当前进度

**第 1、2、3 步已验收；当前为第 4 步：本地海报、资料库搜索筛选与离线显示。**

- 主界面以海报网格显示记录，保持添加时间倒序；顶部搜索已保存的中文名或原名，可与“全部 / 电影 / 剧集”筛选组合使用。搜索和筛选只读取本机数据。
- 海报下载后保存在本机，海报墙和详情共用缓存；重开应用、断网时优先读取本地文件。之前添加的记录在打开资料库时自动补存海报。
- 联网添加时输入片名搜索 TMDB，只显示第一页候选；选中后获取中文资料、原名、年份、类型、导演 / 主创和前 5 位主演。中文简介为空时再请求英文，并显示“英文简介”。
- 观看日期默认今天；个人评分需主动选择 1–10 的整数，短评可空；剧集额外填写正在看到的季数。
- 新记录在海报缓存完成后可以保存；图片下载失败时给出中文提示，仍允许保存文字资料，之后可重试海报。OMDb 补充评分独立加载，未配置或请求失败不影响保存。
- 保存后打开详情。影片资料、平台评分和个人信息作为快照保存在本机；重复添加提供“打开已有记录”，不会覆盖个人信息。
- 设置页每把 Key 都有“验证”按钮，验证已保存的值。新输入需先保存；验证结果只保留在本次运行中，更换 / 清除 Key 后会重置。
- TMDB Key 以 `eyJ` 开头或去掉首尾空白后长度超过 64 时，显示 Token 提示；只提示，不阻止保存，也不用于判定 Key 是否有效。
- 编辑与删除将在第 5 步完成。

## 在 Xcode 中验证第 4 步

1. scheme 选择 `MovieJournal`，设备选择 `My Mac`。若旧程序还在运行，先按 `⌘.` 停止，再按 `⌘R` 重新编译启动。
2. 首次使用本步骤时保持联网，等待主界面“正在保存海报到本机”的提示消失。若出现下载失败提示，恢复网络后点击“重试海报”。旧记录不用重复添加。
3. 确认主界面出现海报网格，最近添加的记录排在前面。点击“电影”“剧集”“全部”，检查显示的作品类型和数量。
4. 在主界面搜索框输入“肖申克”或 `Breaking Bad`，应只显示本机已有的匹配记录；再切换类型筛选。搜索不存在的片名应显示“没有符合条件的记录”，可点“清除搜索和筛选”恢复。
5. 在线添加另一部作品，填写个人评分和必要的剧集季数，等待“正在将海报保存到本机”结束后保存。新记录应排在海报墙最前面。
6. 按 `⌘Q` 退出，断开网络，再按 `⌘R` 运行。已成功缓存的海报、详情、评分和短评都应正常显示，主界面搜索和筛选仍可使用。离线期间不需要重新填写 Key。
7. 仍在断网时进入“添加观影记录”并搜索片名，应看到中文网络错误和重试入口。恢复网络后可继续正常搜索。
8. 按 `⌘U` 运行常规测试。可选真实接口测试默认跳过；普通测试不会使用真实 TMDB / OMDb Key。

主界面搜索框用于查找**已经保存的记录**；搜索尚未保存的作品，请点击“添加观影记录”。海报从未下载成功时，断网只能显示占位图，文字资料照常可读。

## 海报如何保存在本机

图片保存在应用沙盒的 `Application Support/MovieJournal/Posters/`，与资料库一起持久保留。目录选择参考 [Apple 文件系统说明](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)。数据库使用 V1 已有的 `posterFilename` 字段保存相对文件名，本步骤不改变数据库版本。

候选、添加页、海报墙和详情共用同一份 `w500` 海报文件；同一张图片正在下载时复用请求。写入前用系统 ImageIO 确认图片可解码，再原子写入。缓存损坏或文件缺失时可重新下载；首次升级后需联网补存此前的海报。

缺失海报时显示占位图；网络失败、下载内容不是图片或目录不可写时显示中文提示。资料库提供“重试海报”，重试成功后刷新卡片和详情，不修改个人评分、短评或添加时间。

## 在 Xcode 中验证第 3 步（已通过）

1. scheme 选择 `MovieJournal`，设备选择 `My Mac`，按 `⌘R`，再按 `⌘,` 打开设置。
2. 确认 TMDB 显示“已保存”，点击对应的“验证”，有效时下方显示“有效”。OMDb 是可选项，填写、保存后也可验证。验证未完成时显示进度；无效、网络失败和服务暂不可用分别提示。
3. 返回主界面，点击“添加观影记录”，搜索“肖申克的救赎”，选中 1994 年的电影。检查海报、导演、前 5 位主演、简介和 TMDB 评分。
4. 保留或修改观看日期，选择自己的评分，可填写短评，然后保存。应进入该条记录的详情。
5. 同样搜索“绝命毒师”，选中 2008 年的剧集，检查主创、主演和评分，填写看到第几季，再保存。
6. 按 `⌘Q` 退出，再按 `⌘R`。两条记录仍应存在；点击海报可查看已保存的个人信息和影片资料。
7. 再次搜索并选择同一作品，应提示已添加，并可打开已有记录，数量不增加、个人信息不被覆盖。
8. 按 `⌘U` 运行常规自动化测试。`LiveAPISmokeTests` 默认跳过，避免常规测试自动使用真实 Key 和消耗接口请求。

海报未提供或下载失败时显示占位图，不阻止保存。第 4 步起，已下载的海报也会持久保存在本机。

## Key 验证与 Token 提示

- TMDB 验证调用 `GET /3/authentication`。
- OMDb 验证按固定 IMDb 编号 `tt0111161` 试查一次。验证成功只表示 Key 可用于该请求，不保证每部作品都有 IMDb / 烂番茄评分。
- 请求额度耗尽或服务故障时提示“暂时无法验证”，不会错误判断 Key 无效。
- 保存疑似 Token 时显示“这看起来是 Read Access Token，请填写较短的 API Key（v3）”，同时照常保存。该场景已用假钥匙串测试，不需要替换真实 Key 来运行常规测试。
- Key 仅在按钮验证或获取影片时从钥匙串读取；不输出到日志，不写入源代码、偏好设置或测试记录。

## 可选真实接口验收

以下命令会在已签名的应用测试进程中读取本机保存的 TMDB Key，只访问官方 HTTPS 服务。它验证两部指定作品的真实搜索、导演 / 主创、前 5 位主演、TMDB 评分、真实海报落盘，以及临时数据库与海报缓存重开；离线读取阶段用禁止联网的测试传输层确认不发请求。不会向正式观影记录添加测试数据，也不修改这台 Mac 的网络设置。

```sh
TEST_RUNNER_MOVIEJOURNAL_LIVE_API_TESTS=1 xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' -only-testing:MovieJournalTests/LiveAPISmokeTests test
```

常规测试使用假网络响应、假 Key 和独立临时数据库。OMDb 的真实评分需要用户填写有效 Key 后在界面验收；常规测试覆盖其评分解析、缺失、无效 Key 和服务失败。

## 第 2 步的验收步骤（已通过）

1. scheme 选择 `MovieJournal`，设备选择 `My Mac`，按 `⌘R` 启动，按 `⌘,` 打开设置。
2. 可以先用 `test-tmdb-A` 和 `test-omdb-A` 这类临时文字验证存储流程。每项独立点击“保存”，应显示已保存，输入框变空。OMDb 也可以一直留空。
3. 按 `⌘Q` 退出，再运行并打开设置，保存状态仍应存在，输入框保持空白。设置页不会回显已经保存的 Key。
4. 输入另一段临时文字并保存，验证更换操作可完成。真实替换后的内容由钥匙串往返测试核对，界面不显示明文。
5. 分别清除两把 Key，确认只影响对应项目。清除 TMDB 后点击添加，应提示先填写 TMDB Key，并能点击“打开设置”。
6. 第 2 步最初仅完成存储；第 3 步已接入验证按钮和影片搜索。
7. 按 `⌘U` 运行常规 Swift Testing 测试。常规钥匙串测试只使用隔离的随机条目和假值，运行后清理。

如取消系统的钥匙串授权或保存失败，应用会保留输入并显示中文错误，可以重试。主窗口、添加页和设置页共享保存状态；还可点击“重新检查保存状态”。

## 第 1 步的验收步骤（已通过）

1. 打开 `MovieJournal.xcodeproj`，scheme 选择 `MovieJournal`，运行设备选择 `My Mac`。
2. 按 `⌘R`。主窗口应显示“观影记录”“还没有观影记录”和“0 部作品”。
3. 点击空状态按钮或工具栏 `+`，应打开添加基础页面；按 Esc 或点击“关闭”返回。
4. 第 1 步时设置为基础页面；第 2 步起已替换为真实钥匙串设置。
5. 使用 `⌘Q` 退出，再按 `⌘R` 启动，窗口正常打开。当前未添加真实记录，所以仍为空。
6. 按 `⌘U` 运行 Swift Testing 测试，确认全部通过。

持久化验收由测试完成：在磁盘数据库写入电影、剧集资料，离开写入作用域后重新创建容器并核对字段。测试数据不是联网查询结果，其中的评分只是固定测试值，不代表平台当前评分。

命令行验证（项目根目录）：

```sh
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' build
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' test
```

## 第 1 步验证记录（2026-10-27）

- 环境：Xcode 27.1（27A9275），本机 macOS 27.0.1，arm64；工程最低部署版本仍为 macOS 14。
- `xcodebuild build`：通过，退出码 0。
- `xcodebuild test`：通过，8 项测试、共 9 次执行（评分测试有两个参数），0 失败、0 跳过。
- 应用已实际启动，沙盒内本地资料库已创建；界面显示和按钮点击请按上方步骤手动验证。
- `.xcodeproj/project.pbxproj` 与共享 scheme 均已和修改前文件逐字节比较，保持一致。

## 第 2 步验证记录（2026-10-27）

- `xcodebuild build`：通过，退出码 0；保持现有本地签名及 macOS 14 部署目标。
- `xcodebuild test`：通过，16 项测试、共 17 次执行，0 失败、0 跳过、无运行时警告。
- 新增设置测试覆盖：只查存在性、空白不删除旧值、更换失败可重试、分别清除、取消操作保留输入，以及访问失败与未配置的区分。
- 真实钥匙串往返测试覆盖：保存、独立服务实例读取、更换、两种来源互不影响、清除及重复清除；使用随机 service 与假值并完成清理。
- 第 1 步的全部持久化测试也再次通过。项目配置、共享 scheme、V1 模型与原持久化实现没有改动。
- 页面显示、系统授权窗口与按钮点击仍按上方步骤手动验收。

## 第 3 步验证记录（2026-10-28）

- `xcodebuild build`（Debug / My Mac arm64）：通过，退出码 0。
- 常规 `xcodebuild test`：39 项测试、共 42 次执行，0 失败、0 跳过、无运行时警告。此轮用 `-skip-testing:MovieJournalTests/LiveAPISmokeTests` 排除可选真实接口测试。
- 新增测试覆盖中文第一页搜索、电影 / 剧集资料解析、英文简介回退、补充评分缺失与失败、无效 Key 与网络故障区分、Token 只提示仍保存，以及旧请求晚返回时不覆盖新选择。
- 添加流程覆盖个人评分 / 季数必填、取消不写库、重复记录不覆盖、OMDb 加载中或 Key 无效仍可保存，以及保存后重开数据库。
- 已单独显式运行真实 TMDB 验收：1 项测试通过。使用本机保存的 Key，确认“肖申克的救赎”（电影 278）和“绝命毒师”（剧集 1396）的真实搜索、导演 / 主创、前 5 位主演、TMDB 评分、可解码海报，以及临时数据库保存后重开；未写入正式观影记录。
- 常规测试结果：`/private/tmp/MovieJournal-Step3-FinalTests.xcresult`；真实接口结果：`/private/tmp/MovieJournal-Step3-LiveTests.xcresult`。这些文件不加入 Git。
- 应用和测试包的 `codesign --verify --deep --strict` 均通过，Team 保持 `4DK6SF45V9`。现有工程文件只有 Xcode 自动整理的顺序与引号变化，解析后的配置与上次提交一致。
- V1 持久化模型、迁移计划、原有存储实现及钥匙串实现未修改；没有新增依赖。
- 页面布局和按钮操作仍需按上方步骤在 Xcode 手动验收；OMDb 的真实评分需填写有效 Key 后验证。第 3 步验收时仅支持文字资料离线读取，后续第 4 步加入了海报持久缓存。

## 第 3 步连续搜索崩溃修复（2026-10-28）

- 触发方式：获取“绝命毒师”的资料并显示表单后，在同一添加窗口再次搜索“七武士”。旧表单移除时仍被 SwiftUI / 中文输入法读取，原先将可空草稿直接转换成不可空 Binding 的写法会触发 `BindingOperations.ForceUnwrapping.get(base:)` 崩溃。
- 已读取暂停进程的调用栈，并用自动化测试在旧实现中重现相同的 `EXC_BREAKPOINT / SIGTRAP` 和函数位置；修复后该测试通过。
- 修复：旧表单退出时读取安全快照；每次编辑使用独立的临时编号，旧表单迟到的写入不能恢复已清空草稿，也不能覆盖新草稿。当前表单的个人信息编辑与补充评分更新保持正常。
- 新增 3 项测试、共 4 次执行，覆盖再次搜索、当前表单编辑与评分更新、切换不同作品及重新选择同一作品。未修改 V1 数据库模型、钥匙串或网络接口。
- `xcodebuild build`：通过，退出码 0。全部常规测试：42 项、共 46 次执行，0 失败、0 跳过、无运行时警告；本轮仍排除可选真实接口测试。
- 回归测试结果：`/private/tmp/MovieJournal-DraftBinding-FinalTests.xcresult`。失败复现与进程采样只留在本机诊断目录 / 临时目录，不加入 Git。
- 手动复验：在 Xcode 按 `⌘.` 停止旧进程，再按 `⌘R` 重新构建运行。搜索并选择“绝命毒师”，待表单出现后，再搜索并选择 1954 年的电影“七武士”；可以继续来回搜索、编辑评分和短评，确认界面响应正常。该界面操作仍需手动验收。

## 第 4 步验证记录（2026-10-28）

- `xcodebuild build`（Debug / My Mac arm64）：通过，退出码 0。
- 常规 `xcodebuild test`：57 项测试、共 62 次执行，0 失败、0 跳过、无运行时警告。本轮显式排除 `LiveAPISmokeTests`。
- 新增 15 项测试、共 16 次执行：覆盖图片落盘后新实例离线读取、共用下载与调用者取消、缓存损坏重下、无效图片 / HTTP 错误 / 存储失败、中文名与原名组合搜索筛选、添加时间排序、旧记录补存、失败重试、新记录海报准备、迟到请求隔离，以及补存取消。
- 真实 TMDB 验收单独运行 1 项并通过：两部指定作品的真实资料与海报下载后写入临时资料库和海报目录，重建数据库与缓存实例后，两张海报均能解码；离线读取阶段的测试传输层收到 0 个请求。
- 常规测试结果：`/private/tmp/MovieJournal-Step4-Tests-Full.xcresult`；真实接口结果：`/private/tmp/MovieJournal-Step4-LiveTests.xcresult`。这些文件不加入 Git。
- App 与测试包 `codesign --verify --deep --strict` 均通过，实际 Team 均为 `4DK6SF45V9`。
- 工程配置、V1 模型、迁移计划、钥匙串实现及此前连续搜索修复保持不变；没有新增第三方依赖。资料库只补充 V1 已有的海报相对文件名。
- 界面布局、按钮操作和断网重启仍按上方“验证第 4 步”手动验收。首次运行本版本请先联网完成此前记录的海报补存。

## 代码位置

- `App/`：应用入口。
- `Models/`：V1 版本模型、电影 / 剧集类型、影片资料值对象、个人草稿和迁移计划。
- `Persistence/`：本地容器、显式保存、查重与查询。
- `Networking/`：HTTP 请求、TMDB / OMDb 响应解析与中文错误分类。
- `Services/`：钥匙串、Key 验证、组合资料获取，以及海报文件缓存。
- `ViewModels/`：设置验证状态、添加流程、请求取消、查重、保存，以及资料库搜索筛选与旧记录海报补存。
- `Views/`：启动状态、海报墙、联网添加、观影表单、详情与设置；公共海报和资料展示放在 `Components/`。
- `MovieJournalTests/`：Swift Testing 测试；常规测试隔离资源，可选真实接口验收需显式启用。

## 已确认的数据规则

- 每部作品一条记录，用 `电影/剧集类型 + TMDB ID` 识别作品。保存入口主动查重，重复时返回已有记录编号，不覆盖个人信息。
- 观看日期必填、默认今天；剧集指最近观看日期。我的评分为 1–10 整数且必填，短评可空。
- 剧集保存看到第几季，允许该季尚未看完；电影不保存季数。
- 保存资料快照，包括中文名、原名、年份、类型、简介及语言、导演 / 主创、前 5 位主演、可空的各平台评分、海报相对文件名。
- 中文简介为空时，网络层再获取英文简介，标记“英文简介”；两种都无内容时显示“暂无简介”。演职员姓名直接使用 TMDB 返回值。
- 搜索仅第一页。电影、剧集分别用 `append_to_response` 取齐详情及相关信息。OMDb 失败不阻止保存。

## 本地存储与版本

应用使用沙盒内的 `Application Support/MovieJournal/MovieJournal.store`，明确关闭 CloudKit 同步。数据库无法打开时显示中文错误和“重试”，不会删除数据库或用新空库覆盖。

当前模型为 `MovieJournalSchemaV1`（1.0.0），通过 `Schema(versionedSchema:)` 和 `MovieJournalMigrationPlan` 建立资料库。发布 V1 后保留原版本定义，将来新增 V2 并声明迁移路径。

设计参考：[Apple 的 SwiftData 模型与版本迁移说明](https://developer.apple.com/videos/play/wwdc2023/10195/)。

## 钥匙串与开发签名

Key 通过 Security 框架存为 Generic Password，使用应用专属 service 和每个来源独立的 account；明确设置 `kSecAttrSynchronizable = false`，不参与 iCloud 钥匙串同步。Key 不写入 SwiftData、偏好设置、源码或日志。

当前工程已配置开发团队 `4DK6SF45V9`。App 和测试目标的 Debug、Release 均使用 **Automatically manage signing + Apple Development**。应用标识为 `io.github.pengde-dede.MovieJournal`。

API Key 继续使用 macOS 默认的文件钥匙串，服务名为 `io.github.pengde-dede.MovieJournal.api-keys`。设置状态只检查项目是否存在，不取出密码内容；更换先更新旧项，找不到时才新增，不采用先删除后保存。

如果每次重新编译后都询问钥匙串权限，常见原因是本地临时签名随构建变化，钥匙串未把新构建识别为同一个已授权身份。钥匙串会根据应用的签名要求跟踪访问权限；这与 TMDB/OMDb Key 本身是否有效是两件事。

重新配置开发签名时，在 Xcode 中：

1. `Xcode → Settings → Accounts` 添加自己的 Apple ID。
2. 选择 **MovieJournal target → Signing & Capabilities**，启用 **Automatically manage signing**。
3. **Team** 选择自己的可用开发团队，使用 **Apple Development** 签名证书，保持 Bundle Identifier 不变。
4. 如果测试 target 也提示签名问题，选择同一团队。重新构建运行后，旧钥匙串项目可能还需重新授权一次。

第 2 步最初交付时使用本地临时签名，随后按用户要求配置了上述开发团队。证书私钥由本机钥匙串管理，不放入工程或 Git 仓库。应用遇到钥匙串权限拒绝或取消时显示错误，允许手动重试。

“构建时 codesign 访问 Apple Development 私钥”的提示属于签名证书授权。弹窗所需的是“登录”钥匙串密码，通常与 Mac 用户登录密码一致；直接在系统弹窗输入后，可选择“始终允许”。运行时访问“观影记录 · TMDB/OMDb API Key”的提示则对应应用保存的 Key。

参考：[Apple 的 Mac 钥匙串说明](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)、[代码签名与钥匙串访问身份](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)、[Xcode 应用签名说明](https://help.apple.com/xcode/mac/current/en.lproj/dev3a05256b8.html)。

## 开发团队签名验证（2026-10-27）

- Team：`4DK6SF45V9`，使用用户在 Xcode 创建的 Apple Development 证书。
- App 与测试目标的 Debug / Release 均配置同一 Team 和自动签名。
- `xcodebuild build`（Debug）：通过，退出码 0。
- `xcodebuild test`：通过，16 项测试、共 17 次执行，0 失败、0 跳过。
- `codesign --verify --deep --strict`：应用和测试包均通过；两者的实际 `TeamIdentifier` 都是 `4DK6SF45V9`，签名身份均为 Apple Development。
- 本次仅更新已有工程的签名字段和本文档；不包含任何证书私钥或 API Key。提交仅保存在本地，Git 推送由用户决定。

## 接口与来源

- [TMDB 搜索](https://developer.themoviedb.org/reference/search-multi)、[Key 验证](https://developer.themoviedb.org/reference/authentication-validate-key)。
- 电影合并 `credits,external_ids`；剧集合并 `aggregate_credits,external_ids`，采用[覆盖整部剧的演员表](https://developer.themoviedb.org/reference/tv-series-aggregate-credits)。
- [OMDb 官方参数说明](https://www.omdbapi.com/)。
- 设置页包含 TMDB 署名声明；蓝色 Logo 原样来自 TMDB 官方开发文档引用的 [Logo 资源](https://files.readme.io/29c6fee-blue_short.svg)。

## 后续步骤（等待逐步确认）

5. 编辑、删除确认及完整异常与验收场景。

每完成一步：运行构建与测试，验证通过后做一次中文 Git 提交，再等待确认。
