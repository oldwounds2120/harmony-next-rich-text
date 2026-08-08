# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [1.0.2] - 2026-08-08

### 新增
- **链接打开浏览器开关**：新增 `config.linkOpenBrowser`（**默认 true**）。未传
  `onLinkClick` 回调时，点击链接默认用系统浏览器打开；传了回调始终以回调为准
  （组件不跳转），便于使用方在回调里做自定义行为（弹窗/复制/站内跳转等）；
  置 false 可关闭默认跳转

### 修复
- **表格不渲染（严重）**：后端常见的 `<table><tbody><tr>…</tr></tbody></table>`
  结构以及 `<div class="entry-content">` 包裹正文时，表格整体不渲染、内容被压成纯文本。
  根因与修复：
  - `pushTable` 只收集 table 直接子 `tr`，`tbody` 容器被跳过 → 递归穿透
    `thead/tbody/tfoot` 等容器收集 `tr`；
  - 容器（div 等）内块级子标签原直接遍历子节点，导致 table/标题/代码块/列表/分割线
    落入兜底分支退化为普通文本或丢失 → 新增 `processBlock` 统一分发，容器与顶层共用；
  - `isBlockTag` 补充 `h1~h6`，div 内标题不再退化为正文；
  - 表格列数改为按 colspan 展开统计，支持跨列单元格的列模板
- **同一行内单元格不撑满行高**：某单元格换行变高时，同行的矮单元格背景铺不满整行、
  露出边框底色。`TableBlock` 改为委托独立组件 `TableBlockView`：通过 `onAreaChange`
  测量每行最高单元格高度，全部行测出后给 GridItem 与内层 Column 同时加
  `constraintSize({ minHeight })`，同一行矮单元格被撑满、背景铺满（保持只用
  `columnsTemplate`；`rowsTemplate` 固定行列模式实测只渲染第一行，勿用）
- **表格最后一行没有下边框**：Grid 底部补 1vp 同色横线（`rowsGap` 只产生行间缝隙）
- **新增 5 个表格样式配置项**：`tableHeaderTextColor` / `tableHeaderTextWeight` /
  `tableEvenRowBackground` / `tableOddRowBackground`（斑马纹）/ `tableMinRowHeight`
  （最小行高兜底，0 = 不设下限）
- **引用块高度异常**：左侧竖线改用 `Row` 边框实现。原 `Column().height('100%')` 在
  父容器自适应 + 外层 Scroll 无界高度约束下被解析成最大可用高度，把引用块撑到异常大
  （实测 669vp，与内容多少无关），现高度完全由内容驱动
- **引用块背景内空白**：内部首块 `marginTop`、末块 `marginBottom` 清零，段间距不再
  落在背景内部造成底部多余空白（中间块保留间距作段落分隔）
- **混排链接换行顶对齐错位**：文本 + `<br>` + 链接/图片混排时按"视觉行"拆分渲染
  （构建层按 `\n` 拆行并填充 `RenderBlock.groupLines`，组件层逐行独立 Flex），修复
  含换行文本组与单行链接/文本组在同一 Flex 顶对齐导致链接被顶到上一行的错位；
  链接内嵌 `<br>` 拆段后每段保留 `href` 仍可点击

## [1.0.1] - 2026-08-05

### 修复
- **图片渲染大图自适应**：段内大图（带 width/height）现在会按屏幕宽度自适应铺满，不再撑爆布局；
  小图标/表情保持原尺寸不放大（新增 `largeImageRatio` 配置项，默认 0.6）
- **图片预览手势**：新增双指捏合缩放（1~4 倍）、放大后单指拖动查看细节；
  修复拖动时画面"来回跑"（位移累计语义错误 + Swiper 手势冲突）
- **图片预览序号**：点击第 N 张图打开预览从第 N 张开始（不再停在首张）
- **安全加固**：链接/图片 URL 协议白名单，拦截 `javascript:` / `vbscript:` 伪协议
- **代码块**：内容不足屏幕宽度时保持左对齐（不再居中）
- **ForEach key 稳定性**：改用内容稳定 key，为后续增量渲染/懒加载扫清隐患
- 修复 `$images` / `$previewIndex` 未定义变量导致的预览闪退

## [1.0.0] - 2026-08-04

首个稳定版发布。

### 新增
- 手写递归下降 HTML 解析器（实体解码、属性解析、未闭合标签容错、script/style 内容跳过）
- ArkUI 原生渲染，不依赖 WebView 与系统 RichText 组件
- 支持标签：`h1-h6` / `p` / `strong` / `em` / `u` / `del` / `a` / `img` / `ul` / `ol` / `li`（嵌套）/ `blockquote` / `pre` / `code` / `table`（含 colspan/rowspan）/ `hr` 等
- 样式三层级联：父级继承 → 标签默认样式 → 内联 `style` 属性
- 图片：占位背景、加载失败回调、点击全屏预览（Swiper 滑动 + 双击缩放）
- 代码块：横向滚动 + 轻量语法高亮（注释/字符串/关键字/数字/函数）
- 集中式样式配置 `RichTextConfig`
- 逻辑层单元测试（53 条断言）
- ohpm 三方库标准结构（`oh-package.json5` + 包级入口 `Index.ets`）

### 修复
- ArkTS 编译器兼容性问题（struct 命名冲突、`this` 于静态方法、字符串下标、`LengthMetrics` 参数类型等）
