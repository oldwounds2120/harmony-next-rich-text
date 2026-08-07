# htmlrichtext 新功能开发方案（存档）

> 存档日期：2026-08-06
> 状态：**方案已确认冻结，暂缓实施**（当前优先修 bug，功能按阶段另行排期）
> 版本策略：全部为向后兼容的新增 API，按 SemVer 走 **MINOR**（1.1.0 / 1.2.0 / 1.3.0）

## 1. 功能总览

| # | 功能 | 核心 API | 难度 | 阶段 | 发版 |
|---|---|---|---|---|---|
| ④ | 解析异常兜底 | `onParseError?: (error: ParseError) => void` | ★ | 一 | 1.1.0 |
| ② | AST 导出（读写双入口） | `onParseComplete` / `preprocessAst` / `RichNode.clone()` / `toJSON()` | ★ | 一 | 1.1.0 |
| ① | 解析缓存 | `ParseCache`（静态 LRU）+ `enableCache` / `cacheSize` | ★★ | 二 | 1.2.0 |
| ③ | 自定义节点渲染钩子 | `customNodeRender?: (node, position) => void` | ★★★★ | 三 | 1.3.0 |

## 2. 各功能详细设计

### ④ onParseError（阶段一）

```ts
onParseError?: (error: ParseError) => void
// ParseError { message: string; stage: 'parse' | 'build'; html: string; cause?: Error }
```

- `rebuild()` 整条 parse+build 包 try/catch：异常 → 回调 → 降级渲染（默认空态，可配 `fallback:'text'` 纯文本）→ 组件不闪退
- 附带修复：`decodeEntities` 中超范围码点（如 `&#x110000;`）触发 `String.fromCodePoint` 抛 `RangeError` 的隐患
- 说明：解析器本为容错设计，此回调价值在"保底 + 可观测"；`onParseWarning`（自动补全/多余闭合收集）留 backlog，v1 不做

### ② AST 导出（阶段一，读写双入口）

```ts
onParseComplete?: (ast: RichNode) => void   // 只读观察：分析/提取/统计/转换
preprocessAst?:   (ast: RichNode) => void   // 可写预处理：过滤/替换/插入，影响本次渲染
// 公共工具（RichNode 上）
clone(): RichNode    // 深拷贝：业务在只读回调里要改树做自己的事时自取
toJSON(): object     // 序列化：埋点/调试
```

- 时序：`parse（或缓存命中）→ onParseComplete(ast) → preprocessAst(ast) → build → 渲染`
- 二次处理用法：
  - 读型（图片列表/摘要/统计/转 Markdown/敏感词扫描）→ `onParseComplete` 遍历树即可，树本身不动
  - 写型（过滤节点/替换文本/插入节点）→ `preprocessAst` 是**唯一可写窗口**，改动直接影响本次渲染
  - 边界场景（改树但不影响组件）→ `onParseComplete` 里 `ast.clone()` 后随便改
- 安全设计：可写窗口只在 preprocessAst；缓存开启时组件内部先 clone 再交给 preprocessAst，防污染缓存树；onParseComplete 保持只读约定
- **类型冻结**：`RichNode` 对外公开后字段变更属破坏性更新（触发 MAJOR），1.x 冻结，README 写明稳定性承诺
- 缓存联动：缓存命中时两个回调**依然照常触发**（业务埋点/统计不依赖是否命中），缓存只省"解析"这一步

### ① 解析缓存（阶段二）

```ts
// RichTextConfig 新增
enableCache: boolean = true
cacheSize: number = 32
// 新增 core/ParseCache.ets：模块级静态 LRU（Map 迭代顺序实现）
get(html): RichNode | undefined / put(html, root) / clear()
```

- 只缓存 `html → RichNode`（解析树，与 config/baseUrl 无关，永远安全）；跨组件实例共享；命中后 build 仍每次重跑
- 与阶段一的关系：**同一个缓存**。1.1.0 无缓存，每次真解析；1.2.0 上线后自动联动，业务无感知，回调行为一致
- 缓存树为共享引用 → 靠"preprocessAst 内 clone 保护 + onParseComplete 只读约定"双保险

### ③ customNodeRender（阶段三）

```ts
customNodeRender?: (node: RichNode, position: 'block' | 'inline') => void  // 业务侧 @Builder 函数传入
```

- 抽取**已知标签全集 KNOWN_TAGS**（现有块级分发链 + `INLINE_TAGS` + void/skip 集中管理）
- 块级未知标签 → `RenderBlock{kind:'custom', customNode}` → `BlockBuilder` 调钩子
- 行内未知标签 → `InlineGroup{kind:'custom', customNode}` → `TextBlock` Flex 分支调钩子（可与文本/图片/链接混排）
- **未配钩子时保持现有降级逻辑（按文本渲染），行为零变化**，向后兼容
- 行内钩子建议渲染轻量内容（块级内容可能撑爆 Flex），文档注明

## 3. 实施阶段与发版

| 阶段 | 内容 | 预计 | 发版 |
|---|---|---|---|
| 一 | onParseError + AST 导出（含 clone/toJSON） | 0.5 天 | **1.1.0** |
| 二 | 解析缓存 | 0.5~1 天 | **1.2.0** |
| 三 | customNodeRender（块级+行内） | 1~2 天 | **1.3.0** |

三阶段相互独立、均可单独发版（MINOR，兼容不破坏）。分开原因：风险隔离（缓存放大共享引用风险）、独立回滚、changelog 归因清晰、测试焦点不交织。

## 4. 改动文件清单

| 文件 | 改动 |
|---|---|
| `htmlrichtext/src/main/ets/core/ParseCache.ets` | **新增**：静态 LRU 缓存 |
| `htmlrichtext/src/main/ets/core/RichTextConfig.ets` | +`enableCache` / `cacheSize` / `fallback` |
| `htmlrichtext/src/main/ets/core/RichTextModels.ets` | `RenderBlock`+custom 块字段；`ParseError`；`RichNode.clone()/toJSON()` |
| `htmlrichtext/src/main/ets/core/RichTextBuilder.ets` | 抽取 `KNOWN_TAGS`；未知标签 → custom 块 / 行内 custom 组 |
| `htmlrichtext/src/main/ets/core/HtmlParser.ets` | 超范围码点防护 |
| `htmlrichtext/src/main/ets/components/HtmlRichText.ets` | 接入全部新 API + try/catch + 缓存 + preprocessAst clone 保护 |
| `htmlrichtext/src/main/ets/Index.ets` | 导出 `ParseCache` / `ParseError` / 新类型 |
| `test/` | 补：未知标签、LRU 淘汰、clone、错误捕获用例；`run.ts` 注册 |
| `demo/` + `README.md` | customNodeRender 示例（真机验证 @Builder 传递）+ 新 API 文档 |

## 5. 风险与注意

1. **@Builder 参数传递**（阶段三）：唯一有技术不确定性的点。ArkUI 对 `@Builder` 函数传参有限制（不能用匿名箭头函数、不能存 `@State`），**需 demo 真机验证**；备选 `@BuilderParam` / 内嵌组件
2. **缓存树共享引用**：preprocessAst 内 clone 保护 + onParseComplete 只读约定，双保险
3. **RichNode 类型冻结**：1.x 承诺，README 声明
4. **KNOWN_TAGS 维护**：后续加标签支持需同步，建议加单测断言内置标签都在全集内

## 6. 已确认 / 待拍板

**已确认（2026-08-06）**：
- 三阶段分开做，三次 MINOR 发版（1.1.0 → 1.2.0 → 1.3.0）
- AST 导出采用读写双入口（onParseComplete 只读 + preprocessAst 可写 + clone/toJSON）
- customNodeRender 块级 + 行内双覆盖，单钩子带 `position` 参数
- 解析缓存只缓存解析树（RichNode），静态跨实例 LRU

**实施前待拍板**：
- API 命名：`onParseComplete` vs 豆包建议的 `onAstReady`（倾向维持前者）
- `clone()` / `toJSON()` 是否进 1.1.0（还是拆到后续）
- `onParseError` 降级策略细节：默认空态 + `fallback:'text'` 可配是否够用
