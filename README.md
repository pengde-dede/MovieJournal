# 观影记录 · MovieJournal

**简体中文** · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

用海报、评分和短评，留下看过的电影与剧集。

MovieJournal 是使用 SwiftUI 和 SwiftData 开发的 macOS 原生应用，最低支持 macOS 14，使用系统框架构建，观影记录保存在本机。

## 功能

- **海报资料库** — 按添加时间倒序浏览，按中文片名或原名搜索，并切换全部、电影、剧集筛选。
- **联网添加** — 搜索 TMDB 并选择作品，获取片名、年份、类型、导演或主创、前五位主演、简介、海报和 TMDB 评分。
- **个人观影记录** — 保存观看日期、1–10 分的整数评分、可选短评，以及剧集看到的季数。
- **补充评分** — 配置可选的 OMDb API Key 后，在添加时获取 IMDb 和烂番茄评分。
- **离线浏览与编辑** — 查看已经保存的资料和下载成功的海报，离线修改个人观影信息。
- **查重与确认删除** — 重复添加时打开已有记录；删除前确认，并按剩余记录引用清理海报。
- **钥匙串存储** — 在设置中保存、验证、更换或清除 API Key。

## 开始使用

1. 克隆仓库并用 Xcode 打开工程。

   ```sh
   git clone https://github.com/pengde-dede/MovieJournal.git
   cd MovieJournal
   open MovieJournal.xcodeproj
   ```

2. 使用能编译本项目的 Xcode。原有开发记录使用 Xcode 27.1；macOS 14 是应用部署下限。
3. 在 **Signing & Capabilities** 中启用 **Automatically manage signing**，为应用和测试 target 选择自己的开发团队。
4. scheme 选择 **MovieJournal**，设备选择 **My Mac**，按 **⌘R** 运行。
5. 按 **⌘,** 打开设置，填入并保存 **TMDB API Key（v3）**，点击「验证」。使用 API Key（v3 auth）；较长的 Read Access Token 会触发格式提示。
6. 如需补充评分，可填写已激活的 **OMDb API Key**。可分别在官方页面申请。[TMDB API 设置](https://www.themoviedb.org/settings/api) · [OMDb API Key](https://www.omdbapi.com/apikey.aspx)

## 记录一部作品

点击「添加观影记录」，输入片名并从搜索结果中选择正确的作品。确认资料后，填写观看日期和个人评分，也可以写一句短评。剧集需要填写正整数季数，例如 `2`，允许记录尚未看完的这一季。

当前 GitHub 版本在海报准备结束后允许保存；海报下载失败时仍可保存文字资料，稍后在资料库重试。OMDb 未配置、评分缺失或请求失败时，补充评分可留空。

保存后进入详情页，可以编辑个人信息或确认删除。主界面搜索用于查找已经保存的作品；新增作品使用添加窗口。

## 数据与当前范围

| 项目 | 行为 |
| --- | --- |
| 作品标识 | 每部电影或剧集一条记录，以媒体类型和 TMDB ID 查重 |
| 日期与评分 | 日期默认今天；剧集为最近观看日期；个人评分必填，范围为 1–10 的整数 |
| 搜索结果 | 联网搜索显示第一页候选 |
| 影片资料 | 优先获取中文；中文简介为空时回退到英文并标明语言 |
| 平台评分 | 作为本地资料快照保存，OMDb 返回的评分可能为空 |
| 数据库 | 应用沙盒内的 `Application Support/MovieJournal/MovieJournal.store`，使用 V1 版本模型 |
| 海报 | 已保存作品的图片保存在同目录下的 `Posters/`；搜索缩略图使用内存缓存 |
| 离线使用 | 可读取已保存资料和已缓存海报，也可编辑或删除记录 |
| 同步与密钥 | 数据本地存储，CloudKit 同步关闭；API Key 存放在 macOS 钥匙串，iCloud 钥匙串同步关闭 |

应用界面当前使用中文。本页顶部的语言链接用于切换 README 文档语言。

## 构建与测试

在项目根目录运行构建和常规测试，或在 Xcode 中按 **⌘U**。

```sh
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' build
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' test
```

常规测试使用模拟网络、测试 Key 和独立临时资料库。可选的真实 TMDB 验收需要显式启用，并会读取本机保存的 TMDB Key、消耗接口请求。

```sh
TEST_RUNNER_MOVIEJOURNAL_LIVE_API_TESTS=1 xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' -only-testing:MovieJournalTests/LiveAPISmokeTests test
```

真实接口测试在临时资料库中验证搜索、资料获取、海报缓存及离线编辑、删除流程。界面点击、键盘、窗口关闭和断网重启的人工验收步骤保存在开发记录中。

## 项目结构

| 路径 | 职责 |
| --- | --- |
| `MovieJournal/App/` | 应用入口 |
| `MovieJournal/Models/` | 版本模型、影片资料、个人草稿和迁移计划 |
| `MovieJournal/Persistence/` | 本地容器、查询、显式保存、查重与回滚 |
| `MovieJournal/Networking/` | TMDB / OMDb 请求、解析和错误处理 |
| `MovieJournal/Services/` | 钥匙串、Key 验证、资料获取、海报缓存与清理 |
| `MovieJournal/ViewModels/` | 添加、编辑、删除、设置和资料库状态 |
| `MovieJournal/Views/` | SwiftUI 页面与共用组件 |
| `MovieJournalTests/` | Swift Testing 测试及可选真实接口验收 |

## 开发记录

原 README 中的分阶段验收步骤、历史测试结果、问题修复、签名和存储说明已完整保留。历史验证结果对应记录中的版本和日期。[完整开发记录（中文）](docs/DEVELOPMENT.zh-CN.md)

## 数据来源与致谢

影片资料和海报来自 TMDB，IMDb 和烂番茄补充评分由 OMDb 提供。[TMDB API](https://developer.themoviedb.org/reference/intro/getting-started) · [OMDb API](https://www.omdbapi.com/)

This product uses the TMDB API but is not endorsed or certified by TMDB.
