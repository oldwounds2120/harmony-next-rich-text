/**
 * HtmlRichText.ets
 * 鸿蒙 NEXT 自定义富文本解析组件（资讯/文章详情页场景）
 *
 * 用法：
 *   HtmlRichText({
 *     html: this.htmlContent,
 *     config: new RichTextConfig(),
 *     baseUrl: 'https://cdn.example.com',
 *     onLinkClick: (url: string) => { this.openUrl(url) },
 *     onImageClick: (index: number, url: string) => {}
 *   })
 *
 * 特性：
 *  - 手写 HTML 解析器 + 样式继承，支持 h1-h6/p/strong/em/u/del/a/img/ul/ol/li/
 *    blockquote/pre/code/table/hr/br/span/div 等标签与内联 style
 *  - 文本用 Text+Span 原生渲染，换行连续，样式精细可控
 *  - 图片支持占位背景、加载失败回调、点击全屏预览（Swiper + 双击缩放）
 *  - 代码块支持横向滚动与轻量语法高亮
 *  - 所有样式集中在 RichTextConfig，可整体定制
 */
import { LengthMetrics, display } from '@kit.ArkUI';
// 注意：onAreaChange 回调的 Area 类型为全局声明类型，无需（也不能）从 @kit.ArkUI 导入
import {
  RenderBlock, InlineGroup, RichSpan, TableCell, AlignStyle, DecorationStyle, FontStyleType
} from '../core/RichTextModels';
import { RichTextConfig } from '../core/RichTextConfig';
import { HtmlParser } from '../core/HtmlParser';
import { RichTextBuilder } from '../core/RichTextBuilder';
import { ImagePreviewDialog } from './ImagePreviewDialog';

function toArkAlign(a: AlignStyle): TextAlign {
  switch (a) {
    case AlignStyle.CENTER:
      return TextAlign.Center;
    case AlignStyle.END:
      return TextAlign.End;
    case AlignStyle.JUSTIFY:
      // ArkUI TextAlign 无 Justify 枚举，退化为左对齐
      return TextAlign.Start;
    default:
      return TextAlign.Start;
  }
}

function toArkDeco(d?: DecorationStyle): TextDecorationType {
  switch (d) {
    case DecorationStyle.UNDERLINE:
      return TextDecorationType.Underline;
    case DecorationStyle.LINE_THROUGH:
      return TextDecorationType.LineThrough;
    case DecorationStyle.OVERLINE:
      return TextDecorationType.Overline;
    default:
      return TextDecorationType.None;
  }
}

function toArkFontStyle(f?: FontStyleType): FontStyle {
  return f === FontStyleType.ITALIC ? FontStyle.Italic : FontStyle.Normal;
}

@Component
export struct HtmlRichText {
  /** 富文本 HTML 字符串（变化时自动重新解析） */
  @Prop @Watch('onHtmlChange') html: string = ''
  /** 样式配置（建议父组件持有单例） */
  config: RichTextConfig = new RichTextConfig()
  /** 图片/链接相对地址前缀 */
  baseUrl: string = ''
  /** 链接点击回调 */
  onLinkClick?: (url: string) => void
  /** 图片点击回调（index 为整篇文章中的图片序号） */
  onImageClick?: (index: number, url: string) => void
  /** 图片加载失败回调 */
  onImageLoadError?: (url: string) => void
  /**
   * 屏幕宽度（vp），可选入参：由使用方传入可避免组件自取；
   * 未传入时组件在 aboutToAppear 中通过 display 获取（兜底 360vp）。
   * TODO(折叠屏/分屏适配)：display.getDefaultDisplaySync() 只取一次，
   * 分屏/折叠态变化时屏幕宽度不会自动刷新，后续需监听窗口尺寸变化更新此值。
   */
  screenWidthVp: number = -1

  @State private blocks: RenderBlock[] = []
  @State private images: string[] = []
  @State private previewIndex: number = 0

  private previewCtrl: CustomDialogController | null = null

  aboutToAppear(): void {
    // 屏幕宽度：优先使用方传入，否则组件自取（物理像素 ÷ 密度 → vp），失败兜底 360
    if (this.screenWidthVp <= 0) {
      try {
        const d = display.getDefaultDisplaySync();
        this.screenWidthVp = d.width / d.densityPixels;
      } catch (e) {
        this.screenWidthVp = 360;
      }
    }
    this.rebuild();
  }

  aboutToDisappear(): void {
    this.previewCtrl?.close();
    this.previewCtrl = null;
  }

  onHtmlChange(propName: string): void {
    this.rebuild();
  }

  /**
   * 重新构建渲染模型：HTML → 解析树 → 渲染块（仅在此处做解析与构建，
   * build() 里零计算，纯渲染；html 变化时由 @Watch 触发）。
   * 同时收集全文图片地址列表（按出现顺序），供预览弹窗 Swiper 使用。
   */
  private rebuild(): void {
    const root = HtmlParser.parse(this.html);
    const builder = new RichTextBuilder(root, this.config, this.baseUrl);
    this.blocks = builder.build();
    this.images = [];
    this.collectImages(this.blocks);
    this.previewIndex = 0;
  }

  /** 递归收集所有图片（含块级 img 与行内 img group），保持出现顺序 */
  private collectImages(blocks: RenderBlock[]): void {
    for (const b of blocks) {
      if (b.kind === 'image' && b.imageSrc.length > 0) {
        this.images.push(b.imageSrc);
      }
      for (const g of b.groups) {
        if (g.kind === 'image' && g.src.length > 0) {
          this.images.push(g.src);
        }
      }
      this.collectImages(b.children);
    }
  }

  /** 打开图片预览：总是先回调 onImageClick；预览开关开启时弹出全屏 Swiper */
  private openImage(index: number, src: string): void {
    this.onImageClick?.(index, src);
    if (this.config.enableImagePreview && this.images.length > 0) {
      this.previewIndex = index;
      this.openPreview();
    }
  }

  /**
   * 打开预览弹窗：每次打开前重建 CustomDialogController。
   * 原因：弹窗的 images/currentIndex 是构造时快照（普通参数，非 @Link），
   * 且 rebuild() 会更换 images 数组引用——重建保证 currentIndex 从点击的图片开始、
   * images 为最新列表（修复"点第 N 张图预览却停在首张"问题）。
   */
  private openPreview(): void {
    this.previewCtrl?.close(); // 先关旧弹窗（若存在），再重建，避免重复弹窗
    this.previewCtrl = new CustomDialogController({
      builder: ImagePreviewDialog({
        images: this.images,
        currentIndex: this.previewIndex
      }),
      customStyle: true,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      backgroundColor: '#00000000',
      width: '100%',
      height: '100%'
    });
    this.previewCtrl.open();
  }

  private onImageTap(src: string): void {
    const idx: number = this.images.indexOf(src);
    this.openImage(idx < 0 ? 0 : idx, src);
  }

  /**
   * 大图判定：图片 HTML 声明的宽度 ≥ 屏幕宽度 × largeImageRatio → 正文大图，
   * 渲染时自适应铺满；未声明宽度一律视为小图（不放大，安全选择）。
   * 判定只依赖图片自身声明宽度，与排版上下文（混排/独占）无关。
   */
  private isLargeImage(g: InlineGroup): boolean {
    const w = g.width;
    if (w === undefined || w <= 0) {
      return false;
    }
    return w >= this.screenWidthVp * this.config.largeImageRatio;
  }

  private blockToGroup(block: RenderBlock): InlineGroup {
    const g: InlineGroup = new InlineGroup();
    g.kind = 'image';
    g.src = block.imageSrc;
    g.alt = block.imageAlt;
    g.width = block.imageWidth;
    g.height = block.imageHeight;
    g.borderRadius = this.config.imageRadius;
    return g;
  }

  /**
   * 生成内容稳定的 ForEach key（替换 index.toString()）：
   * key = 类型前缀 + 内容特征（文本取前 16 字符、图片取 src、链接取 href），
   * 再拼接出现序号保证同级唯一。
   * 优点：内容不变时 key 稳定，ArkUI 组件可正确复用；内容变化时 key 改变，强制重建。
   */
  private stableKey(kind: string, text: string, seq: number): string {
    let content = text;
    if (content.length > 16) {
      content = content.substring(0, 16);
    }
    return kind + '_' + content + '_' + seq.toString();
  }

  /** 取 RenderBlock 的内容特征：文本块取首个 span 文本，图片取 src，其余取 kind */
  private blockKeyText(block: RenderBlock): string {
    if (block.kind === 'text' || block.kind === 'heading') {
      if (block.groups.length > 0 && block.groups[0].spans.length > 0) {
        return block.groups[0].spans[0].text;
      }
      return '';
    }
    if (block.kind === 'image') {
      return block.imageSrc;
    }
    if (block.kind === 'table') {
      return block.tableRows.length.toString();
    }
    return block.kind;
  }

  /** 取 InlineGroup 的内容特征：文本取首个 span 文本，图片取 src，链接取 href */
  private groupKeyText(g: InlineGroup): string {
    if (g.kind === 'text') {
      return g.spans.length > 0 ? g.spans[0].text : '';
    }
    if (g.kind === 'link') {
      return g.href;
    }
    return g.src;
  }

  // ================= 渲染 =================

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.blocks.length > 0) {
          ForEach(this.blocks, (block: RenderBlock) => {
            this.BlockBuilder(block)
          }, (block: RenderBlock, index: number) => this.stableKey(block.kind, this.blockKeyText(block), index))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
  }

  @Builder
  private BlockBuilder(block: RenderBlock) {
    Column() {
      if (block.kind === 'text' || block.kind === 'heading') {
        this.TextBlock(block)
      } else if (block.kind === 'image') {
        this.ImageBlock(block)
      } else if (block.kind === 'code') {
        this.CodeBlock(block)
      } else if (block.kind === 'quote') {
        this.QuoteBlock(block)
      } else if (block.kind === 'list-item') {
        this.ListItemBlock(block)
      } else if (block.kind === 'table') {
        this.TableBlock(block)
      } else if (block.kind === 'hr') {
        this.HrBlock()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: block.marginTop, bottom: block.marginBottom })
    .padding({ left: block.paddingLeft })
  }

  // ---------- 文本段 ----------

  /**
   * 文本段渲染：
   *  - 纯文本（单一 text 组）→ 单个 Text，支持 text-align 居中/右对齐等；
   *  - 混排（文本 + 图片 + 链接）→ Flex wrap 布局：
   *      每个文本组是一个 Text（多 Span 连片），图片是 Image，链接是带 onClick 的 Text；
   *      Flex 自动换行，文本组内部保持自然断行，图片/链接作为独立可交互子项。
   *  - 链接的点击由组件层在此处绑定（Span 不支持点击事件，所以链接单独成组）。
   */
  @Builder
  private TextBlock(block: RenderBlock) {
    if (block.groups.length === 1 && block.groups[0].kind === 'text') {
      // 纯文本段：单个 Text，支持 textAlign
      Text() {
        this.SpanList(block.groups[0].spans)
      }
      .lineHeight(block.lineHeight)
      .textAlign(toArkAlign(block.textAlign))
      .width('100%')
    } else {
      // 混排（文本 + 图片 / 链接）：Flex wrap，文本连片、图片/链接独立
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        ForEach(block.groups, (g: InlineGroup) => {
          if (g.kind === 'text') {
            Text() {
              this.SpanList(g.spans)
            }
            .lineHeight(block.lineHeight)
            .textAlign(TextAlign.Start)
          } else if (g.kind === 'link') {
            Text() {
              this.SpanList(g.spans)
            }
            .lineHeight(block.lineHeight)
            .textAlign(TextAlign.Start)
            .onClick(() => {
              if (this.onLinkClick !== undefined) {
                this.onLinkClick(g.href);
              }
            })
          } else if (g.kind === 'image') {
            // 行内图片也按声明宽度判定是否为大图：大图自动升级为自适应渲染
            this.InlineImage(g, this.isLargeImage(g))
          }
        }, (g: InlineGroup, index: number) => this.stableKey(g.kind, this.groupKeyText(g), index))
      }
      .width('100%')
    }
  }

  /**
   * 行内 Span 渲染：一个 Text 内的多个 Span 共享同一基线，实现
   * "同一行内多种样式"（加粗/斜体/颜色/上下标混排）。
   * 每个属性都给兜底值，避免某个 Span 缺字段时样式串到别的 Span。
   * 注意：baselineOffset 在 API 12+ 参数类型是 LengthMetrics，需用
   * LengthMetrics.vp() 包装；API 11 工程请改回直接传 number（见 README 环境要求）。
   */
  @Builder
  private SpanList(spans: RichSpan[]) {
    ForEach(spans, (sp: RichSpan) => {
      Span(sp.text)
        .fontSize(sp.fontSize ?? this.config.bodyFontSize)
        .fontWeight(sp.fontWeight ?? 400)
        .fontStyle(toArkFontStyle(sp.fontStyle))
        .decoration({ type: toArkDeco(sp.decoration), color: sp.decorationColor })
        .fontColor(sp.color ?? this.config.bodyColor)
        .backgroundColor(sp.backgroundColor ?? '#00000000')
        .fontFamily(sp.fontFamily ?? this.config.bodyFontFamily)
        .baselineOffset(LengthMetrics.vp(sp.baselineOffset ?? 0))
        .letterSpacing(sp.letterSpacing ?? 0)
    }, (sp: RichSpan, index: number) => this.stableKey('span', sp.text + (sp.color ?? ''), index))
  }

  // ---------- 图片 ----------

  @Builder
  private ImageBlock(block: RenderBlock) {
    Column() {
      // 块级图片：始终按大图处理（自适应铺满）
      this.InlineImage(this.blockToGroup(block), true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 行内/块级图片渲染（四档，按优先级判定，不可调换顺序）：
   *  1. isBlock=true（块级图片/判定为大图）：铺满容器宽度，高度按原图比例自适应
   *     （等同 CSS width:100%; height:auto），忽略 PC 编辑器设置的固定宽高。
   *     ⚠️ 必须排最前：正文插图常带 width+height，若 height 分支在前会被短路，
   *     大图自适应永远不生效。
   *  2. 有宽有高（小图）：按固定尺寸渲染（Cover 裁剪避免变形）；
   *  3. 有宽无高：按声明宽度渲染，高度等比，maxWidth 100% 防溢出；
   *  4. 无宽高：按原始像素尺寸显示、不放大，maxWidth 100% 防溢出（避免小图标被拉大变形）。
   *  - backgroundColor 作为加载中的占位底色；onError 抛出加载失败回调；
   *  - onClick 触发全屏预览（config.enableImagePreview 可关闭，仅留回调）。
   */
  @Builder
  private InlineImage(g: InlineGroup, isBlock: boolean = false) {
    if (isBlock) {
      // 档1：块级/大图 → 铺满宽度，等比自适应（忽略 PC 固定宽高）
      Image(g.src)
        .width('100%')
        .objectFit(ImageFit.Contain)
        .borderRadius(g.borderRadius ?? this.config.imageRadius)
        .backgroundColor(this.config.imagePlaceholderColor)
        .constraintSize({ maxWidth: '100%' })
        .margin({ top: this.config.imageMargin, bottom: this.config.imageMargin })
        .onClick(() => {
          this.onImageTap(g.src);
        })
        .onError(() => {
          if (this.onImageLoadError !== undefined) {
            this.onImageLoadError(g.src);
          }
        })
    } else if (g.height !== undefined) {
      // 档2：有宽有高（小图）→ 固定尺寸渲染（Cover 裁剪避免变形）
      Image(g.src)
        .width(g.width ?? '100%')
        .height(g.height)
        .objectFit(ImageFit.Cover)
        .borderRadius(g.borderRadius ?? this.config.imageRadius)
        .backgroundColor(this.config.imagePlaceholderColor)
        .constraintSize({ maxWidth: '100%' })
        .margin({ top: this.config.imageInlineMargin, bottom: this.config.imageInlineMargin })
        .onClick(() => {
          this.onImageTap(g.src);
        })
        .onError(() => {
          if (this.onImageLoadError !== undefined) {
            this.onImageLoadError(g.src);
          }
        })
    } else if (g.width !== undefined) {
      // 档3：有宽无高 → 按声明宽度渲染，高度等比，不拉满
      Image(g.src)
        .width(g.width)
        .objectFit(ImageFit.Contain)
        .borderRadius(g.borderRadius ?? this.config.imageRadius)
        .backgroundColor(this.config.imagePlaceholderColor)
        .constraintSize({ maxWidth: '100%' })
        .margin({ top: this.config.imageInlineMargin, bottom: this.config.imageInlineMargin })
        .onClick(() => {
          this.onImageTap(g.src);
        })
        .onError(() => {
          if (this.onImageLoadError !== undefined) {
            this.onImageLoadError(g.src);
          }
        })
    } else {
      // 档4：无宽高 → 按原始像素尺寸显示、不放大；maxWidth 100% 防溢出
      Image(g.src)
        .objectFit(ImageFit.Contain)
        .borderRadius(g.borderRadius ?? this.config.imageRadius)
        .backgroundColor(this.config.imagePlaceholderColor)
        .constraintSize({ maxWidth: '100%' })
        .margin({ top: this.config.imageInlineMargin, bottom: this.config.imageInlineMargin })
        .onClick(() => {
          this.onImageTap(g.src);
        })
        .onError(() => {
          if (this.onImageLoadError !== undefined) {
            this.onImageLoadError(g.src);
          }
        })
    }
  }

  // ---------- 代码块 ----------

  /**
   * 代码块渲染要点：
   *  - 按"行"拆成多个独立 Text（每行一个），长行不会被 Text 自动换行，
   *    而是撑宽内容 → 外层 Scroll 横向滚动（scrollable(Horizontal)）；
   *  - 空格已在构建阶段替换为不换行空格 \u00A0，保证缩进/对齐精确显示；
   *  - 空行用 \u00A0 占位，避免行高塌陷；
   *  - codeLinesTokens 是构建阶段算好的高亮结果（RichSpan[]，含颜色），
   *    渲染时零计算。
   */
  @Builder
  private CodeBlock(block: RenderBlock) {
    Column() {
      Scroll() {
        Column() {
          ForEach(block.codeLinesTokens, (tokens: RichSpan[], lineIndex: number) => {
            this.CodeLine(tokens, lineIndex)
          }, (tokens: RichSpan[], lineIndex: number) => this.stableKey('codeLine',
            tokens.length > 0 ? tokens[0].text : '', lineIndex))
        }
        // 撑满 Scroll 视口宽度：横向滚动时 Column 默认按内容宽度自适应，
        // 代码行短于屏幕时会被居中；width('100%') 让代码行始终从左开始。
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(this.config.codeBlockPadding)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
    }
    .width('100%')
    .backgroundColor(this.config.codeBlockBackground)
    .borderRadius(this.config.codeBlockRadius)
  }

  @Builder
  private CodeLine(tokens: RichSpan[], lineIndex: number) {
    if (tokens.length === 0) {
      Text('\u00A0')
        .fontFamily(this.config.codeFontFamily)
        .fontSize(this.config.codeBlockFontSize)
        .lineHeight(this.config.codeBlockFontSize * this.config.codeBlockLineHeight)
    } else {
      Text() {
        ForEach(tokens, (sp: RichSpan) => {
          Span(sp.text)
            .fontColor(sp.color ?? this.config.codeBlockTextColor)
            .fontSize(this.config.codeBlockFontSize)
        }, (sp: RichSpan, index: number) => this.stableKey('codeToken', sp.text + (sp.color ?? ''), index))
      }
      .fontFamily(this.config.codeFontFamily)
      .fontSize(this.config.codeBlockFontSize)
      .lineHeight(this.config.codeBlockFontSize * this.config.codeBlockLineHeight)
      .fontColor(this.config.codeBlockTextColor)
    }
  }

  // ---------- 引用块 ----------

  @Builder
  private QuoteBlock(block: RenderBlock) {
    Row() {
      Column()
        .width(3)
        .height('100%')
        .backgroundColor(this.config.quoteBorderColor)
        .borderRadius(2)
      Column() {
        ForEach(block.children, (child: RenderBlock) => {
          this.BlockBuilder(child)
        }, (child: RenderBlock, index: number) => this.stableKey(child.kind, this.blockKeyText(child), index))
      }
      .layoutWeight(1)
      .margin({ left: 10 })
    }
    .width('100%')
    .backgroundColor(this.config.quoteBackground)
    .borderRadius(6)
    .padding(this.config.quotePadding)
    .alignItems(VerticalAlign.Top)
  }

  // ---------- 列表项 ----------

  @Builder
  private ListItemBlock(block: RenderBlock) {
    Row() {
      Text(block.listMarker)
        .fontSize(block.children.length > 0 ? block.children[0].fontSize : this.config.bodyFontSize)
        .fontColor(this.config.listMarkerColor)
        .width(18)
        .margin({ right: 4 })
      Column() {
        ForEach(block.children, (child: RenderBlock) => {
          this.BlockBuilder(child)
        }, (child: RenderBlock, index: number) => this.stableKey(child.kind, this.blockKeyText(child), index))
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // ---------- 表格 ----------

  /**
   * 表格渲染：委托独立组件 TableBlockView（见文件底部）。
   * 委托原因：行高测量（onAreaChange）需要组件实例持有每行测量状态，
   * @Builder 方法无法持有独立状态；TableBlockView 负责：
   *  - 行内等高：测量每行最高单元格高度，给该行所有 GridItem/内层 Column 加
   *    minHeight，同一行矮单元格被撑满、背景铺满整行（问题 1）；
   *  - 斑马纹 / 表头文字色字重（走 RichTextConfig 新配置项）；
   *  - Grid 底部补 1vp 横线（问题 3：rowsGap 只产生行间缝隙，最后一行无下边框）。
   */
  @Builder
  private TableBlock(block: RenderBlock) {
    TableBlockView({ config: this.config, block: block })
  }

  // ---------- 分割线 ----------

  @Builder
  private HrBlock() {
    Row()
      .width('100%')
      .height(1)
      .backgroundColor(this.config.hrColor)
  }
}

/**
 * TableBlockView - 表格渲染独立组件（HtmlRichText 委托调用）
 *
 * 解决三个实测问题（详见 docs/表格行高与边框问题及修改建议-20260807.md）：
 *  1. 行内不等高：同一行某单元格换行变高时，矮单元格背景铺不满整行、露出边框底色。
 *     方案：通过 rowSpan===1 单元格的 onAreaChange 上报高度，每行取最大值作为该行行高；
 *     全部行测出后写入 @State rowMinHeights，给 GridItem 与内层 Column 同时加
 *     constraintSize({ minHeight })，让 Grid 采纳行高、矮单元格被撑满、背景铺满。
 *     - minHeight 必须同时作用到 GridItem 上（仅内层 Column 不足以让 Grid 采纳行高）；
 *     - rowSpan>1 的跨行单元格不参与测量，避免污染单行行高；
 *     - 值无变化时不重新赋值 @State，避免 onAreaChange→重渲染→再 onAreaChange 循环。
 *  2. 不用 rowsTemplate 固定行列模式（实测只渲染第一行），始终只用 columnsTemplate。
 *  3. 最后一行无下边框：rowsGap 只产生行间缝隙，Grid 底部补 1vp 同色横线。
 *
 * 注意事项：
 *  - 独立 @Component 才能持有每行测量状态（@Builder 方法无法持有实例状态）；
 *  - 未测出行高（如全表 rowSpan>1 / 测量失败）时 rowMinHeights 保持 0 = 自然行高，
 *    安全降级为原始行为，不会丢行。
 */
@Component
struct TableBlockView {
  config: RichTextConfig = new RichTextConfig()
  block: RenderBlock = new RenderBlock()

  /** 每行已测高度（普通成员，非响应式，避免每次 onAreaChange 触发渲染） */
  private measured: number[] = []
  /** 每行最小行高（@State 驱动渲染） */
  @State private rowMinHeights: number[] = []

  private gridTemplate(cols: number): string {
    let t: string = '';
    for (let i = 0; i < cols; i++) {
      t += (i === 0 ? '1fr' : ' 1fr');
    }
    return t;
  }

  /** 单元格内容 → Span 列表（图片在单元格内降级为 alt/[图片] 文本） */
  private cellSpans(cell: TableCell): RichSpan[] {
    const out: RichSpan[] = [];
    for (const g of cell.groups) {
      if (g.kind === 'text' || g.kind === 'link') {
        for (const sp of g.spans) {
          out.push(sp);
        }
      } else if (g.kind === 'image') {
        const sp: RichSpan = new RichSpan();
        sp.text = g.alt.length > 0 ? g.alt : '[图片]';
        out.push(sp);
      }
    }
    return out;
  }

  /**
   * 行高测量上报：rowSpan===1 的 GridItem 上报自身高度，每行取最大值；
   * 全部行都测出（>0）后才写入 rowMinHeights（提前应用会得到偏小的行高）。
   */
  private onRowMeasured(rowIndex: number, height: number): void {
    if (height <= 0) {
      return;
    }
    if (height <= this.measured[rowIndex]) {
      return;
    }
    this.measured[rowIndex] = height;
    // 全部行都测出才应用；未测出保持 0 = 自然行高（安全降级）
    for (const h of this.measured) {
      if (h <= 0) {
        return;
      }
    }
    const mins: number[] = [];
    let changed: boolean = false;
    for (let i = 0; i < this.measured.length; i++) {
      const v: number = Math.max(this.measured[i], this.config.tableMinRowHeight);
      if (v !== this.rowMinHeights[i]) {
        changed = true;
      }
      mins.push(v);
    }
    if (changed) {
      this.rowMinHeights = mins; // 值无变化不赋值，防循环渲染
    }
  }

  /** 单元格背景：表头用表头背景，数据行按行号做斑马纹 */
  private cellBackground(cell: TableCell, rowIndex: number): string {
    if (cell.isHeader) {
      return this.config.tableHeaderBackground;
    }
    return rowIndex % 2 === 0 ? this.config.tableEvenRowBackground : this.config.tableOddRowBackground;
  }

  build() {
    Column() {
      Grid() {
        ForEach(this.block.tableRows, (row: TableCell[], rowIndex: number) => {
          ForEach(row, (cell: TableCell, colIndex: number) => {
            GridItem() {
              Column() {
                Text() {
                  ForEach(this.cellSpans(cell), (sp: RichSpan) => {
                    Span(sp.text)
                      .fontSize(sp.fontSize ?? this.config.bodyFontSize)
                      .fontWeight(cell.isHeader ? this.config.tableHeaderTextWeight : (sp.fontWeight ?? 400))
                      .fontStyle(toArkFontStyle(sp.fontStyle))
                      .decoration({ type: toArkDeco(sp.decoration), color: sp.decorationColor })
                      .fontColor(cell.isHeader ? this.config.tableHeaderTextColor : (sp.color ?? this.config.tableTextColor))
                      .backgroundColor(sp.backgroundColor ?? '#00000000')
                  }, (sp: RichSpan, index: number) => 's' + index.toString())
                }
                .lineHeight(this.config.bodyFontSize * 1.5)
                .width('100%')
              }
              // 内层 Column 同值 minHeight：背景铺满整行、内容顶对齐（未测出时 ??0 = 自然行高）
              .constraintSize({ minHeight: this.rowMinHeights[rowIndex] ?? 0 })
              .justifyContent(FlexAlign.Start)
              .padding(this.config.tableCellPadding)
              .backgroundColor(this.cellBackground(cell, rowIndex))
              .alignItems(HorizontalAlign.Start)
            }
            // 关键：GridItem 也加 minHeight，Grid 才采纳该行行高，行内矮单元格被撑满
            .constraintSize({ minHeight: this.rowMinHeights[rowIndex] ?? 0 })
            .columnStart(colIndex)
            .columnEnd(colIndex + cell.colSpan - 1)
            .rowStart(rowIndex)
            .rowEnd(rowIndex + cell.rowSpan - 1)
            .onAreaChange((_oldV: Area, newV: Area) => {
              if (cell.rowSpan === 1) {
                const h: number = Number(newV.height);
                if (!Number.isNaN(h) && h > 0) {
                  this.onRowMeasured(rowIndex, h);
                }
              }
            })
          }, (cell: TableCell, colIndex: number) => rowIndex.toString() + '-' + colIndex.toString())
        }, (row: TableCell[], rowIndex: number) => rowIndex.toString())
      }
      .columnsTemplate(this.gridTemplate(this.block.tableCols))
      .rowsGap(1)
      .columnsGap(1)
      .backgroundColor(this.config.tableBorderColor)
      .width('100%')
      // 最后一行下边框：rowsGap 只产生行间缝隙，最底部补 1vp 同色横线
      Row()
        .width('100%')
        .height(1)
        .backgroundColor(this.config.tableBorderColor)
    }
    .width('100%')
    .clip(true)
    .borderRadius(4)
  }
}
