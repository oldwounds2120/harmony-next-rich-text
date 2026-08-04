# 鸿蒙 NEXT 自定义富文本解析组件（HtmlRichText）

> [![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE) ![Language](https://img.shields.io/badge/Language-ArkTS-orange.svg) ![Platform](https://img.shields.io/badge/Platform-HarmonyOS%20NEXT-green.svg)

> 不依赖 WebView 和系统 RichText 的自研 HTML 富文本组件，专为资讯/文章详情页设计。
> 手写 HTML 解析器 + ArkUI 原生渲染（Text / Span / Image / Flex / Grid），样式完全可控。

---

## 一、为什么自研？

| 方案 | 问题 |
| ---- | ---- |
| `Web` 组件 | 重、加载慢、交互不原生、与页面主题割裂 |
| 系统 `RichText` | 样式控制弱（行高/间距/字体），图片无法自定义加载与点击预览，`pre/code` 等标签支持不全 |
| **本组件** | 纯 ArkUI 原生渲染，每个标签的样式都可定制，图片可点击全屏预览，代码块支持高亮与横向滚动 |

---

## 二、目录结构

采用 **ohpm 三方库（HAR）标准结构**，可直接发布到 OpenHarmony 三方库中心仓：

```
harmony-next-rich-text/
├── Index.ets                    # 包级统一入口（oh-package.json5 的 main）
├── oh-package.json5             # ohpm 包元数据（包名/版本/作者/协议/关键词）
├── README.md                    # 本文档
├── CHANGELOG.md                 # 版本变更记录
├── LICENSE                      # Apache-2.0 协议全文
├── NOTICE                       # 版权归属声明（Apache 规范）
├── .gitignore
├── src/main/ets/htmlrichtext/   # 组件源码（HAR 标准源码目录）
│   ├── HtmlRichText.ets         # 主组件（渲染 + 图片预览 + 回调）
│   ├── RichTextConfig.ets       # 样式配置（所有可定制项）
│   ├── HtmlParser.ets           # HTML 解析器（纯逻辑，可单测）
│   ├── RichTextBuilder.ets      # 渲染树构建器：样式继承 / inline 分组（纯逻辑，可单测）
│   ├── RichTextModels.ets       # 数据模型（纯逻辑，可单测）
│   ├── SimpleCodeHighlighter.ets # 轻量代码高亮（纯逻辑）
│   ├── ImagePreviewDialog.ets   # 全屏图片预览弹窗
│   └── Index.ets                # 源码层统一导出
├── demo/
│   └── RichTextDemoPage.ets     # 完整示例页面
└── test/
    └── run.ts                   # 逻辑层单测（53 条断言）
```

---

## 三、环境要求

- 仅支持 **HarmonyOS NEXT（API 12+）**，建议 `compileSdkVersion >= 12`。
- 组件使用了 `Span.baselineOffset(LengthMetrics)`（API 12 起参数类型为 `LengthMetrics`）；
  若你的工程需要兼容 **API 11**，请将 `HtmlRichText.ets` 中
  `.baselineOffset(LengthMetrics.vp(sp.baselineOffset ?? 0))` 一行改回
  `.baselineOffset(sp.baselineOffset ?? 0)` 即可（ArkTS 无条件编译，两种写法按工程 SDK 二选一）。

## 四、快速开始

### 方式 A：ohpm 安装（三方库发布后）

在工程根目录 `oh-package.json5` 的 `dependencies` 中加入：

```json5
"dependencies": {
  "htmlrichtext": "^1.0.0"
}
```

然后执行 `ohpm install`，页面中直接按包名导入：

```ts
import { HtmlRichText, RichTextConfig } from 'htmlrichtext';
```

### 方式 B：源码复制（推荐，即刻可用）

把 `src/main/ets/htmlrichtext` 整个目录复制到你工程的
`entry/src/main/ets/htmlrichtext` 下，导入路径指向源码入口：

```ts
import { HtmlRichText, RichTextConfig } from '../htmlrichtext/Index';
```

### 3. 在你的页面里使用

```ts
import { HtmlRichText, RichTextConfig } from '../htmlrichtext/Index';

@Entry
@Component
struct ArticlePage {
  @State html: string = '<h2>标题</h2><p>正文内容<strong>加粗</strong></p>'
  private config: RichTextConfig = new RichTextConfig()

  build() {
    Scroll() {
      Column() {
        HtmlRichText({
          html: this.html,                 // HTML 字符串（变化会自动重新解析）
          config: this.config,             // 样式配置（可空，用默认值）
          baseUrl: 'https://cdn.example.com', // 图片/链接相对路径前缀（可选）
          onLinkClick: (url: string) => { this.openUrl(url) },   // 链接点击
          onImageClick: (index: number, url: string) => {},      // 图片点击（index 为全文图片序号）
          onImageLoadError: (url: string) => {}                  // 图片加载失败
        })
      }
      .width('100%')
      .padding(16)
    }
  }
}
```

> 想先看效果？把 `demo/RichTextDemoPage.ets` 复制到 `entry/src/main/ets/pages/`，
> 在 `main_pages.json` 注册 `{ "src": "pages/RichTextDemoPage" }` 编译即可。
> 组件放在 `Scroll` 内使用即可，高度自适应内容。

---

## 五、API

### HtmlRichText 参数

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| `html` | `string` | 是 | 富文本 HTML 字符串；变化时自动重新解析渲染 |
| `config` | `RichTextConfig` | 否 | 样式配置，默认内置一套 |
| `baseUrl` | `string` | 否 | 相对图片/链接地址的前缀，`/` 开头或绝对地址不拼接 |
| `onLinkClick` | `(url: string) => void` | 否 | `<a>` 链接点击回调 |
| `onImageClick` | `(index, url) => void` | 否 | 图片点击回调（全组件图片按出现顺序编号） |
| `onImageLoadError` | `(url: string) => void` | 否 | 图片加载失败回调 |

内置能力：点击图片默认打开全屏预览（Swiper 左右滑动 + 双击缩放），可通过
`config.enableImagePreview = false` 关闭。

### RichTextConfig 常用配置

```ts
const config = new RichTextConfig();
config.bodyFontSize = 17;            // 正文字号
config.bodyLineHeight = 1.8;         // 行高（倍数）
config.paragraphSpacing = 14;        // 段间距
config.headingSizes = [22, 20, 18, 17, 16, 15]; // h1~h6 字号
config.linkColor = '#1E6FFF';        // 链接颜色
config.codeBlockBackground = '#F6F8FA'; // 代码块背景
config.enableCodeHighlight = true;   // 代码高亮开关
config.imageRadius = 8;              // 图片圆角
// ... 完整字段见 RichTextConfig.ets
```

---

## 六、支持的标签

| 类别 | 标签 |
| ---- | ---- |
| 标题 | `h1` ~ `h6` |
| 文本 | `p` `span` `div` `strong/b` `em/i` `u/ins` `del/s/strike` `mark` `small` `big` `sub` `sup` |
| 链接 | `a`（点击回调 + 下划线 + 链接色） |
| 图片 | `img` `figure` `figcaption`（占位背景、加载失败回调、点击全屏预览、width/height 属性） |
| 列表 | `ul` `ol` `li`（支持嵌套，圆点/空心圆/方块/数字序号） |
| 代码 | `pre` `code` `kbd` `samp` `tt`（代码块横向滚动 + 轻量语法高亮） |
| 引用 | `blockquote`（左边框 + 背景色） |
| 表格 | `table` `tr` `td` `th`（支持 colspan/rowspan、表头背景、边框） |
| 其他 | `hr` `br` `center` `section` `article` 等 |

另支持：
- 内联 CSS：`color` `font-size` `font-weight` `font-style` `text-decoration`
  `line-height` `letter-spacing` `text-align` `margin` `padding` `border-radius`
  `background-color` `vertical-align` `width` `height`
- HTML 实体：`&amp;` `&lt;` `&gt;` `&nbsp;` `&#39;` `&#x27;` 等
- 容错：标签未闭合自动补全、多余闭合标签忽略、`script/style` 内容跳过

---

## 七、常见问题

**Q：代码高亮效果不满意？**
A：`config.enableCodeHighlight = false` 关闭；或修改 `SimpleCodeHighlighter.ets` 中的配色。

**Q：图片宽度想限制为百分比？**
A：`img` 未指定 `width/height` 时默认占满容器宽度并等比缩放；指定了属性则按指定尺寸
（超出容器宽度会自动约束在 100% 内）。

**Q：希望链接用系统浏览器打开？**
```ts
const context = getContext(this) as common.UIAbilityContext;
context.openLink(url); // 需要 import { common } from '@kit.AbilityKit'
```

**Q：性能怎么样？**
A：解析和渲染模型构建只在 `html` 变化时执行一次（缓存为渲染块数组），渲染用 ForEach
递归生成原生组件。普通文章（几百个节点）无压力。

**Q：想加自定义标签或交互？**
A：改 `RichTextBuilder.ets` 的 `computeStyle` / `walkBlock` 增加规则，再在
`HtmlRichText.ets` 的 `BlockBuilder` 中增加对应渲染分支即可。

---

## 八、逻辑层单测（可选）

解析器/构建器/高亮器为纯 TS 逻辑（无 ArkUI 依赖），可用 Node 直接验证：

```bash
# 将 src/main/ets/htmlrichtext 下的 5 个逻辑层 .ets 复制为 .ts 后运行（Node 22+）
# 需给相对 import 补 .ts 扩展名
cd test
node --experimental-transform-types run.ts
```

---

## 九、参与贡献

欢迎 PR / Issue！无论是新增标签支持、修复 bug、优化渲染性能，还是补充文档：

1. Fork 本仓库并创建你的分支
2. 修改代码，`test/run.ts` 有覆盖解析器/构建器的单测，请保证新改动不破坏现有用例
3. 提交 PR，说明改动内容与动机

## 十、开源协议

本项目基于 [Apache License 2.0](LICENSE) 开源（版权声明见 [NOTICE](NOTICE)）。
你可以自由使用、修改、商用（含闭源项目）；分发或修改时需保留协议与版权声明，
并对修改过的文件加以标注。Apache 协议还包含明确的专利授权条款，对使用者更友好。
如果这个组件帮到了你，欢迎点个 Star ⭐。
