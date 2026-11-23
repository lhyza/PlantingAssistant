# 种植助手 · Android App 源码

一个**完全离线**的多作物种植管理 App：草莓为主，兼带柠檬、葡萄、无花果；管批次、记农活、拍照片、按生产阶段提醒施肥打药，知识库可以用外部 AI 批量扩充（AI 出 zip，App 只负责导入）。

- 应用名：**种植助手**
- 包名：`cn.zhongzhizhushou.planting`
- 技术栈：Flutter 3.50 / Dart 3.14 + SQLite（sqflite）+ 本地通知
- 最新安装包：**1.5.0**（versionCode 6，[下载](#下载)）
- 仓库源码快照：**1.4.0**（versionCode 5，数据库 schema v8，数据文件 schemaVersion 4）
- 特点：**没有 INTERNET 权限**，所有数据只存在手机上，不登录、不联网、不上传

---

## 下载

- [GitHub Releases · v1.5.0](https://github.com/lhyza/PlantingAssistant/releases/tag/v1.5.0)
- 直接下载：[PlantingAssistant-1.5.0-release.apk](https://github.com/lhyza/PlantingAssistant/releases/download/v1.5.0/PlantingAssistant-1.5.0-release.apk)
- 大小：62,555,705 字节（约 59.7 MB）
- SHA-256：`1ebd848a4c3ece6e368452b65bcdfb64e38a8e0962041b2a41901715d945b581`

> 1.5.0 安装包的数据格式标识是 `caomeiyuan.data`；下面源码快照 1.4.0 使用 `planting.data`，两边的 JSON 导出文件不能直接互导。

---

## 主要功能

| 模块 | 能做什么 |
| --- | --- |
| 今天 | 已逾期 / 今天要做 / 接下来几天；顶部显示当前批次的生长阶段与操作要点 |
| 批次 | 按作物分组；定植日推算 10 个草莓阶段（柠檬/葡萄/无花果各 6 个，多年生按本年度萌芽日重置）；合并批次；逐盆标记存活/僵苗/死亡 |
| 记一笔 | 多批次一次记录（每个批次各一条）；施肥/施药可多行复配；浇水/其他；拍照（按批次或按盆，拍完可裁剪） |
| 提醒 | 多批次一次创建、列表合并展示；完成顺延、只做一次、取消提醒；每天 08:00 汇总 + 19:00 逾期补推 |
| 知识库 | 品种 / 病虫害 / 肥料 / 药品 / 土肥五个库，可增删改、可导入导出；品种与病虫害支持图片、裁剪与作物默认图 |
| 生产阶段 | 每个作物一套阶段，每个阶段可配施肥方案、病虫害预防、操作要点与提醒模板（一键生成整套提醒） |
| AI 扩充 | 生成提示词 → 交给豆包/DeepSeek → 拿回 zip → 导入品种或病虫害，图片可后续裁剪确认 |
| 数据 | 7 份 JSON 全量导出（图片内嵌 base64）、本机快照、条目级合并导入（新增/更新/跳过/删除四类） |

---

## 目录结构

```
share/
├─ README.md                 ← 本文件
├─ docs/
│  ├─ App设计文档.md          ← 架构、数据模型、业务规则、页面、导入导出（建议先读这篇）
│  └─ images/                ← 界面线框与真实截图
└─ app/                      ← Flutter 工程（可直接 flutter run / build）
   ├─ lib/
   │  ├─ main.dart           启动：初始化数据库、种子数据、通知
   │  ├─ app.dart            MaterialApp + 主题
   │  ├─ core/               工具、主题、图片存储、版本记录
   │  ├─ data/               模型、SQLite、仓库层、通知、导入导出、AI 提示词与数据包解析
   │  └─ ui/                 全部页面
   ├─ assets/seeds/          内置知识库（4 作物 28 阶段 60 提醒模板 / 20 品种 / 8 病虫害 / 4 土肥）
   ├─ test/                  20 个测试（数据层 + UI 冒烟 + 截图）
   └─ android/               Android 工程（Gradle、Manifest、图标）
```

## 快速开始

```bash
# 1. 环境：Flutter 3.50+（含 Dart 3.14）、JDK 17、Android SDK（compileSdk 37）
flutter --version
java -version

# 2. 安装依赖并跑起来
cd app
flutter pub get
flutter run                     # 接上手机或模拟器

# 3. 测试与打包
flutter test                    # 20 个用例
flutter analyze                 # 应为 0 error
flutter build apk --release     # 产物：build/app/outputs/flutter-apk/app-release.apk
```

### 关于签名

`app/android/app/build.gradle.kts` 会读取 `app/android/key.properties`（**未随源码提供**）：

```properties
storePassword=你的库密码
keyPassword=你的key密码
keyAlias=你的alias
storeFile=相对路径或绝对路径/release.jks
```

没有这个文件时，构建会自动退回到 **debug 签名**，`flutter run` 和本地调试完全不受影响；只有要发布 release 包、且希望**覆盖升级旧版本**时，才必须使用同一把 `.jks`。

## 数据与隐私

- App 不申请网络权限，Android 系统层面就无法联网（可用 `aapt2 dump permissions` 验证）。
- 数据存于 App 私有目录：`files/planting.db`（SQLite）+ `files/images/`（照片）。
- 卸载即清空。**备份方式**：App 内「我的 → 数据管理 → 全部导出」，可导出 7 份 JSON（图片以 base64 内嵌），换机后用「导入」还原。
- 内置知识库只是文本资料，不含任何账号、接口或第三方服务信息。
- 数据文件的格式标识：源码快照 1.4.0 为 `planting.data`，1.5.0 安装包为 `caomeiyuan.data`（见 `lib/data/transfer.dart` 的 `kFormat` 与 `assets/seeds/*.json` 的 `format` 字段）；两边的导出文件不能直接互导。
  **如果你手上还有另一份同款 App 导出的 JSON**，两边 `format` 必须一致才能互相导入；不一致时只改这两个地方即可。

## 更新记录

### 1.5.0（2026-11-23）
- 导入 AI 数据包现在支持直接选 `.json` 文件（手机版豆包也能用）
- `.json` 导入不显示「!」提示，图片可以以后自己补
- 新增导入预览页：先看清「新增 / 更新 / 合并 / 跳过」，可逐条勾选后再写入
- 通用病虫害条目不会被草莓版内容覆盖（自动跳过，需修改请在知识库里直接编辑）
- 疑似同名的条目自动合并，预览页会标出合并到哪一条
- 导入失败时给出具体原因（不是 zip、缺 data.json、选错成数据管理导出文件等）

### 1.4.0（2026-11-23）
- 多批次提醒、AI 模板与导入、病虫害多作物；新建提醒可一次勾选多个批次，列表合并展示

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [App设计文档](docs/App设计文档.md) | 架构分层、13 张表、阶段/提醒/盆位/多批次提醒/病虫害多作物等业务规则、31 个页面、通知、数据文件与 AI 数据包、构建与扩展指南 |
| 界面参考 | `docs/images/app-real-*.png`（真实渲染截图）、`app-mockup.png`（三屏线框）、`v13-mockup.png`（按盆拍照方案）、`v14-mockup.png`（多批次提醒 / AI 模板） |
