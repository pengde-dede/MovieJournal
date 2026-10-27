# 观影记录 · MovieJournal

macOS 原生观影记录应用。使用 SwiftUI + SwiftData，最低 macOS 14，无第三方依赖，数据保存在本机。

## 当前进度

**第 1 步已验收；当前实现第 2 步：API Key 设置与本机钥匙串。**

- 设置页可分别保存、更换、清除 TMDB API Key（v3）与可选 OMDb Key。
- 保存成功后清空输入框，只显示“已保存（尚未联网验证）”。两把 Key 独立操作，留空不会删除旧值。
- 未填写 TMDB Key 时，添加页给出中文提示和打开设置的入口；钥匙串访问失败有单独提示。
- 本步未发起 API 请求，联网搜索仍待第 3 步接入。保存状态表示已存入钥匙串，不表示服务已验证 Key 有效。
- 保留已有 `.xcodeproj`、共享 scheme、签名、沙盒和 V1 数据结构，通过文件夹同步识别新增源文件。

## 在 Xcode 中验证第 2 步

1. scheme 选择 `MovieJournal`，设备选择 `My Mac`，按 `⌘R` 启动，按 `⌘,` 打开设置。
2. 可以先用 `test-tmdb-A` 和 `test-omdb-A` 这类临时文字验证存储流程。每项独立点击“保存”，应显示已保存，输入框变空。OMDb 也可以一直留空。
3. 按 `⌘Q` 退出，再运行并打开设置，保存状态仍应存在，输入框保持空白。设置页不会回显已经保存的 Key。
4. 输入另一段临时文字并保存，验证更换操作可完成。真实替换后的内容由钥匙串往返测试核对，界面不显示明文。
5. 分别清除两把 Key，确认只影响对应项目。清除 TMDB 后点击添加，应提示先填写 TMDB Key，并能点击“打开设置”。
6. 最后换成自己的真实 TMDB API Key（v3 auth）；可选填写 OMDb Key。本步仍不会联网校验，影片搜索在第 3 步实现。
7. 按 `⌘U` 运行全部 Swift Testing 测试。测试只用隔离的随机钥匙串条目和假值，不读取或覆盖应用中真实配置的 Key，运行后清理测试条目。

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

## 代码位置

- `App/`：应用入口。
- `Models/`：V1 版本模型、电影 / 剧集类型、迁移计划。
- `Persistence/`：本地容器、显式保存、查重与查询。
- `Services/KeychainService.swift`：本机钥匙串存取，在独立 actor 中执行。
- `ViewModels/SettingsViewModel.swift`：设置输入、保存状态和中文操作结果，不缓存已保存的密码内容。
- `Views/`：启动状态、海报墙、基础页面和数据库错误提示。
- `MovieJournalTests/`：Swift Testing 测试；数据库使用独立临时目录，钥匙串使用随机 service 和假值。

## 已确认的数据规则

- 每部作品一条记录，用 `电影/剧集类型 + TMDB ID` 识别作品。保存入口主动查重，重复时返回已有记录编号，不覆盖个人信息。
- 观看日期必填、默认今天；剧集指最近观看日期。我的评分为 1–10 整数且必填，短评可空。
- 剧集保存看到第几季，允许该季尚未看完；电影不保存季数。
- 保存资料快照，包括中文名、原名、年份、类型、简介及语言、导演 / 主创、前 5 位主演、可空的各平台评分、海报相对文件名。
- 中文简介为空时，后续网络层再获取英文简介，标记“英文简介”。演职员姓名直接使用 TMDB 返回值。
- 搜索仅第一页。电影、剧集分别用 `append_to_response` 取齐详情及相关信息。OMDb 失败不阻止保存。

## 本地存储与版本

应用使用沙盒内的 `Application Support/MovieJournal/MovieJournal.store`，明确关闭 CloudKit 同步。数据库无法打开时显示中文错误和“重试”，不会删除数据库或用新空库覆盖。

当前模型为 `MovieJournalSchemaV1`（1.0.0），通过 `Schema(versionedSchema:)` 和 `MovieJournalMigrationPlan` 建立资料库。发布 V1 后保留原版本定义，将来新增 V2 并声明迁移路径。

设计参考：[Apple 的 SwiftData 模型与版本迁移说明](https://developer.apple.com/videos/play/wwdc2023/10195/)。

## 钥匙串与开发签名

Key 通过 Security 框架存为 Generic Password，使用应用专属 service 和每个来源独立的 account；明确设置 `kSecAttrSynchronizable = false`，不参与 iCloud 钥匙串同步。Key 不写入 SwiftData、偏好设置、源码或日志。

当前工程使用无 Team 的 `Sign to Run Locally`，因此采用 macOS 默认的文件钥匙串，不启用需要预置描述文件权限的 Data Protection 后端或跨应用访问组。设置状态只检查项目是否存在，不取出密码内容；更换先更新旧项，找不到时才新增，不采用先删除后保存。

如果每次重新编译后都询问钥匙串权限，常见原因是本地临时签名随构建变化，钥匙串未把新构建识别为同一个已授权身份。钥匙串会根据应用的签名要求跟踪访问权限；这与 TMDB/OMDb Key 本身是否有效是两件事。

需要稳定开发签名时，在 Xcode 中：

1. `Xcode → Settings → Accounts` 添加自己的 Apple ID。
2. 选择 **MovieJournal target → Signing & Capabilities**，启用 **Automatically manage signing**。
3. **Team** 选择自己的可用开发团队，使用 **Apple Development** 签名证书，保持 Bundle Identifier 不变。
4. 如果测试 target 也提示签名问题，选择同一团队。重新构建运行后，旧钥匙串项目可能还需重新授权一次。

本步没有修改 Team、申请证书、关闭沙盒或调整用户钥匙串权限。没有可用团队或证书时仍可保留当前本地签名，发生访问提示时按系统授权流程处理。应用不屏蔽或反复自动重试密码授权；拒绝或取消后会显示错误，允许手动重试。

“构建时 codesign 访问 Apple Development 私钥”的提示属于签名证书授权；运行时访问“观影记录 · TMDB/OMDb API Key”的提示才是本应用保存的 Key。

参考：[Apple 的 Mac 钥匙串说明](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)、[代码签名与钥匙串访问身份](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)、[Xcode 应用签名说明](https://help.apple.com/xcode/mac/current/en.lproj/dev3a05256b8.html)。

## 后续步骤（等待逐步确认）
3. TMDB 搜索、自动填写、可选 OMDb 评分、个人信息表单、保存与详情。
4. 持久海报、完整海报墙、本地片名搜索、类型筛选、离线显示。
5. 编辑、删除确认及完整异常与验收场景。

每完成一步：运行构建与测试，验证通过后做一次中文 Git 提交，再等待确认。
