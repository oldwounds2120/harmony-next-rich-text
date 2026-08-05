# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

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
