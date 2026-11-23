/// AI 数据包提示词生成。
///
/// 设计说明见 docs/08-AI提示词设计.md：把「作物 + 知识类型 + 链接」拼成一段
/// 可以整段复制给豆包/DeepSeek 等工具的提示词，对方按约定产出 zip 数据包，
/// App 只负责导入（App 本身没有任何网络权限）。
library;

const int kAiMaxItems = 20;
const String kAiPromptVersion = 'v1';

String aiKindName(String kind) => kind == 'pest' ? '病虫害' : '品种';

/// 生成提示词。kind 取 `variety` / `pest`。
String buildAiPrompt({
  required String cropName,
  required String kind,
  required List<String> links,
  int maxItems = kAiMaxItems,
  String? today,
}) {
  final date = today ?? DateTime.now().toIso8601String().substring(0, 10);
  final linkList = links.isEmpty
      ? '（这次没有给链接，请按你已有的农业知识整理，不要编造不存在的品种名）'
      : links.map((l) => '- $l').join('\n');
  return kind == 'pest'
      ? _pestPrompt(cropName, linkList, maxItems, date)
      : _varietyPrompt(cropName, linkList, maxItems, date);
}

String _varietyPrompt(String crop, String links, int max, String date) => '''
你是一名蔬菜/果树育种与栽培资料整理员。请根据我给的链接内容，整理出【$crop】品种资料，并按下面的格式输出一个可以直接被手机 App 导入的数据包。

## 一、资料链接
$links

## 二、输出要求（必须严格遵守）
1. 最多整理 $max 条，宁少勿滥；只收录链接里确实出现过的品种。
2. 必须产出一个 zip 压缩包，压缩包内包含：
   - `data.json`：UTF-8、无 BOM、缩进 2 空格，结构见下面第三节。
   - `images/` 目录（可选）：每个品种一张图片，文件名用条目 id，例如 `images/var_001.jpg`。没有图就不要放。
3. `data.json` 顶层结构：
```json
{
  "format": "planting.ai",
  "schemaVersion": 1,
  "kind": "variety",
  "crop": "$crop",
  "generatedAt": "$date",
  "promptVersion": "$kAiPromptVersion",
  "count": 3,
  "items": [ ... ]
}
```
4. 每条品种字段如下，全部必填（没有依据的字段填空字符串 ""，不要编造）：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | `var_001` 递增，同一文件内不得重复 |
| name | string | 品种名，不要带括号别称以外的修饰 |
| category | string | 红草莓 / 白草莓 / 或其他你判断的分类，单值 |
| characteristics | string | 特点，40~80 字 |
| suitable | string | 适宜种植条件（地区/季节/容器） |
| care | string | 栽培要点，60~120 字 |
| yield | string | 产量描述，如「单株 300~400g」 |
| taste | string | 口感描述 |
| sweetness | string | 甜度文字描述 |
| sweetnessStar | int | 0~5 的整数 |
| fruitSize | string | 果个文字描述 |
| sizeStar | int | 0~5 的整数 |
| heatResistance | string | 耐热/抗性描述 |
| heatStar | int | 0~5 的整数 |
| image | string | 对应 `images/` 里的相对路径，没有图填 "" |

5. 硬性约束：
   - 三个星级必须是 0~5 的整数，不能写小数、不能写「4.5 星」。
   - 不要在 JSON 里写注释、不要出现 `\\uXXXX` 转义中文。
   - 所有中文字段用简体中文。
   - 不确定的字段留空，不要用「暂无」「待补充」这类占位词。
6. 输出前请自查：count 与 items 数量一致、id 不重复、星级都是整数、每个 image 路径都真实存在于 zip 里。

## 三、最后请给我
1. 一个可下载的 zip 文件（文件名 `$crop-品种-数据包.zip`）；
2. 一句话说明：整理了几条、有几条带图。
''';

String _pestPrompt(String crop, String links, int max, String date) => '''
你是一名植物保护技术员。请根据我给的链接内容，整理【$crop】常见病虫害资料，并输出一个可以被手机 App 导入的数据包。

## 一、资料链接
$links

## 二、输出要求（必须严格遵守）
1. 最多整理 $max 条，只收录确实影响 $crop 的病虫害。
2. 必须产出一个 zip：`data.json` + `images/`（可选，每条一张图，文件名用条目 id）。
3. `data.json` 顶层结构：
```json
{
  "format": "planting.ai",
  "schemaVersion": 1,
  "kind": "pest",
  "crop": "$crop",
  "generatedAt": "$date",
  "promptVersion": "$kAiPromptVersion",
  "count": 3,
  "items": [ ... ]
}
```
4. 每条字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| id | string | `pest_001` 递增 |
| name | string | 病虫害名 |
| category | string | 病害 / 虫害 |
| symptoms | string | 症状识别，50~100 字 |
| cause | string | 发生原因（温度/湿度/传播途径） |
| treatment | string | 防治方法，含药剂名称与大致浓度，80~150 字 |
| prevention | string | 日常预防措施 |
| image | string | `images/` 相对路径，没有图填 "" |

5. 硬性约束：不要编造农药商品名；写了药剂就给通用名与浓度范围；不确定的字段留空。
6. 输出前自查：count 与 items 数一致、id 不重复、image 路径真实存在。

## 三、最后请给我
1. 一个 zip 文件（文件名 `$crop-病虫害-数据包.zip`）；
2. 一句话说明整理了几条、几条带图。
''';

/// 给「导入失败」页面用的简短说明，避免用户一头雾水。
const String kAiPackHint = '''
数据包里应该有 data.json（format=planting.ai），图片放在 images/ 目录。
如果 AI 只给了 JSON 文本，可以先存成 data.json，在同级建 images 文件夹再压缩成 zip。
''';
