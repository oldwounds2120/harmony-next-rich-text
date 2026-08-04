# Changelog

本项目遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

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
