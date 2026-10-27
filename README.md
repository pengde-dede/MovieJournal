# 观影记录 · MovieJournal

macOS 原生观影记录应用。使用 SwiftUI + SwiftData，最低 macOS 14，无第三方依赖，数据保存在本机。

## 当前进度

**第 1 步：工程基础、版本化数据模型、本地资料库、空海报墙及基础导航。**

- 主窗口显示“观影记录”和中文空状态；已接入按添加时间倒序读取的本地资料库。
- “添加观影记录”和“设置”入口可打开基础页面，本步尚不能搜索、添加真实影片或填写 Key。
- 未发起网络请求，未读写钥匙串；测试示例只写入独立临时数据库，不添加到用户的观影记录中。
- 保留已有 `.xcodeproj`、共享 scheme、签名和沙盒设置，通过文件夹同步识别新增源文件。

## 在 Xcode 中验证第 1 步

1. 打开 `MovieJournal.xcodeproj`，scheme 选择 `MovieJournal`，运行设备选择 `My Mac`。
2. 按 `⌘R`。主窗口应显示“观影记录”“还没有观影记录”和“0 部作品”。
3. 点击空状态按钮或工具栏 `+`，应打开添加基础页面；按 Esc 或点击“关闭”返回。
4. 点击工具栏设置按钮或按 `⌘,`，应打开设置基础页面。目前 Key 显示“尚未配置”。
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

## 代码位置

- `App/`：应用入口。
- `Models/`：V1 版本模型、电影 / 剧集类型、迁移计划。
- `Persistence/`：本地容器、显式保存、查重与查询。
- `Views/`：启动状态、海报墙、基础页面和数据库错误提示。
- `MovieJournalTests/`：Swift Testing 测试，各测试使用独立临时目录。

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

## 后续步骤（等待逐步确认）

2. API Key 设置与本机钥匙串。
3. TMDB 搜索、自动填写、可选 OMDb 评分、个人信息表单、保存与详情。
4. 持久海报、完整海报墙、本地片名搜索、类型筛选、离线显示。
5. 编辑、删除确认及完整异常与验收场景。

每完成一步：运行构建与测试，验证通过后做一次中文 Git 提交，再等待确认。
