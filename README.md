# 种植助手 · Android App（Flutter 源码 + 设计文档）

> 版本 **1.8.0**（versionCode 9，数据库 schema v10，数据文件 schemaVersion 5）｜ 2026-11-24
> 一个**离线单机**的盆栽种植管理 App：草莓为主，附带柠檬 / 葡萄 / 无花果。
> 数据只存在手机上，不含账号、服务器与埋点；只有「检查更新、下载新版本」时会联网。

---

## 目录

```
app/                 Flutter 工程（可直接 flutter run / build）
  lib/
    core/            工具函数、主题、图片存取、版本常量、更新记录
    data/            模型、SQLite、仓储、通知、数据文件导入导出、AI 提示词与导入、更新服务
    ui/              30+ 个页面（今天 / 批次 / 记一笔 / 知识库 / 阶段 / 数据 / 我的）
  test/              41 个用例（数据层 / AI 导入 / 更新 / UI 冒烟 / 截图）
  assets/seeds/      内置知识库（首次启动灌入，之后可导入导出）
  android/           原生配置（通知、FileProvider、更新桥接）
docs/
  App设计文档.md      13 章：架构 / 表结构 / 业务规则 / 页面 / 通知 / 图片 / 数据文件 / 构建 / 测试 / 扩展
  images/            界面截图与线框
README.md            本文件
```

## 快速开始

```bash
cd app
flutter pub get
flutter run                 # 连真机或模拟器
flutter test                # 41 个用例
flutter build apk --release # 产物 build/app/outputs/flutter-apk/app-release.apk
```

- Flutter 3.50.x / Dart 3.14，Android SDK 37、minSdk 24。
- 首次启动自动建库并灌入内置数据：4 个作物、28 个阶段、60 条提醒模板、20 个草莓品种、8 条病虫害、4 条土肥。**没有任何示例批次**，打开就是空园子。

### 签名

`android/app/build.gradle.kts` 会读 `android/key.properties`；该文件不在仓库里（含密码）。自己用的话：

```properties
storeFile=你的.jks 的相对路径
storePassword=…
keyAlias=…
keyPassword=…
```

没有 `key.properties` 时构建会回退到 debug 签名——能装能跑，但**不能覆盖升级正式包**（签名不同，装之前要卸载，数据会丢）。

## 主要功能

| 模块 | 内容 |
| --- | --- |
| 今天 | 阶段提示条（**写明是哪一批**，多批次可点标签切换，点条体进批次详情）、已逾期 / 今天要做 / 接下来几天、近 15 天操作（一次多批次可合并成「产品 → 施用：A、B → 未施：C」） |
| 批次 | 按作物分组的批次卡（标题行 = 批次名 + 状态）、合并批次、拖拽排序、逐盆拍照、死亡 / 僵苗标记、开启新一季 |
| 记一笔 | 施肥 / 施药 / 浇水 / 拍照 / 其他；多批次 + 多产品复配；从肥料药品库选品自动带出比例与方式 |
| 提醒 | 循环 / 单次、多批次成组（`groupId`）、完成顺延、取消可恢复、指定时刻本地通知 |
| 知识库 | 品种 / 病虫害 / 肥料 / 药品 / 土肥，可增删改、配图与裁剪、AI 模板生成与 zip/JSON 导入 |
| 生产阶段 | 按作物（v1.7 起按季）配置阶段与提醒模板；从上一季复制会自动跳过同名阶段；可删除阶段（连提醒模板一起软删） |
| 数据 | 7 份 JSON 文件导出 / 导入（图片以 base64 内嵌）、每日自动快照、三层条目级合并 |
| 更新 | 检查 GitHub Release → 镜像下载 → 五项校验 → 调系统安装 |

## 数据与隐私

- 数据库：`<应用私有目录>/planting.db`；图片：`<私有目录>/images/`；导出：`<私有目录>/export/`。
- 无账号、无服务器、无统计 SDK；卸载 App 即清空数据，**请定期「数据管理 → 全部导出」**。
- 仅 v1.6 起为「检查更新」申请了 `INTERNET` 与 `REQUEST_INSTALL_PACKAGES`，日常记账、拍照、通知全部离线。

## 文档

| 文件 | 内容 |
| --- | --- |
| [docs/App设计文档.md](docs/App设计文档.md) | 13 章完整设计：技术架构、13 张表逐字段、业务规则（阶段推算 / 提醒生成 / 多季 / opId）、30+ 页面、通知、图片管线、7 份数据文件与三层合并、构建与测试、扩展指南 |
| docs/images/app-real-*.png | 真实界面截图（今天 / 批次 / 我的） |
| docs/images/v17-mockup.png | v1.7 四屏线框（批次列表 / 今天 / 多季配置 / 记一笔勾选） |
| docs/images/app-mockup.png、config-mockup.png、v13-mockup.png、v14-mockup.png | 早期版本线框，保留作对照 |

## 与主工程的一个差异

本目录是**分享用的副本**：数据文件的 `format` 标记为 `planting.data`（主工程历史上用另一个字符串）。
两个 App 属于不同"数据域"，导出的 JSON 不能互相直接导入——如果只需要一套，统一成同一个 `format` 即可
（改 `lib/data/transfer.dart` 的 `kFormat` 与 `assets/seeds/*.json` 的 `format`）。

## 已知限制

- 多季阶段、多年生模板都是**参考值**，请按本地气候在「生产阶段管理」里改。
- 计划通知依赖系统精确闹钟权限；国产系统深度省电会拦截，需要手动放行并自检「测试通知」。
- 删除为软删除，但界面不提供「恢复」；误删靠每日快照或导出文件找回。
- 应用内更新依赖 GitHub Release 的 `latest` 接口（未认证 60 次/小时，App 每天只查一次）。
