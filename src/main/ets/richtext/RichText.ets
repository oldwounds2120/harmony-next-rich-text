/**
 * RichText.ets
 * 鸿蒙 NEXT 自定义富文本解析组件（资讯/文章详情页场景）
 *
 * 用法：
 *   RichText({
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
import {
  RenderBlock, InlineGroup, RichSpan, TableCell, AlignStyle, DecorationStyle, FontStyleType
} from './RichTextModels';
import { RichTextConfig } from './RichTextConfig';
import { HtmlParser } from './HtmlParser';
import { RichTextBuilder } from './RichTextBuilder';
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

  @State private blocks: RenderBlock[] = []
  @State private images: string[] = []
  @State private previewIndex: number = 0

  private previewCtrl: CustomDialogController | null = null

  aboutToAppear(): void {
    this.previewCtrl = new CustomDialogController({
      builder: ImagePreviewDialog({
        images: $images,
        currentIndex: $previewIndex
      }),
      customStyle: true,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      backgroundColor: '#00000000',
      width: '100%',
      height: '100%'
    });
    this.rebuild();
  }

  aboutToDisappear(): void {
    this.previewCtrl?.close();
    this.previewCtrl = null;
  }

  onHtmlChange(propName: string): void {
    this.rebuild();
  }

  private rebuild(): void {
    const root = HtmlParser.parse(this.html);
    const builder = new RichTextBuilder(root, this.config, this.baseUrl);
    this.blocks = builder.build();
    this.images = [];
    this.collectImages(this.blocks);
    this.previewIndex = 0;
  }

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

  private openImage(index: number, src: string): void {
    this.onImageClick?.(index, src);
    if (this.config.enableImagePreview && this.images.length > 0) {
      this.previewIndex = index;
      this.previewCtrl?.open();
    }
  }

  private onImageTap(src: string): void {
    const idx: number = this.images.indexOf(src);
    this.openImage(idx < 0 ? 0 : idx, src);
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

  private gridTemplate(cols: number): string {
    let t: string = '';
    for (let i = 0; i < cols; i++) {
      t += (i === 0 ? '1fr' : ' 1fr');
    }
    return t;
  }

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

  // ================= 渲染 =================

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.blocks.length > 0) {
          ForEach(this.blocks, (block: RenderBlock) => {
            this.BlockBuilder(block)
          }, (block: RenderBlock, index: number) => index.toString())
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
            this.InlineImage(g)
          }
        }, (g: InlineGroup, index: number) => index.toString())
      }
      .width('100%')
    }
  }

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
        .baselineOffset(sp.baselineOffset ?? 0)
        .letterSpacing(sp.letterSpacing ?? 0)
    }, (sp: RichSpan, index: number) => index.toString())
  }

  // ---------- 图片 ----------

  @Builder
  private ImageBlock(block: RenderBlock) {
    Column() {
      this.InlineImage(this.blockToGroup(block))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private InlineImage(g: InlineGroup) {
    if (g.height !== undefined) {
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
    } else {
      Image(g.src)
        .width(g.width ?? '100%')
        .objectFit(ImageFit.Fill)
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

  @Builder
  private CodeBlock(block: RenderBlock) {
    Column() {
      Scroll() {
        Column() {
          ForEach(block.codeLinesTokens, (tokens: RichSpan[], lineIndex: number) => {
            this.CodeLine(tokens, lineIndex)
          }, (tokens: RichSpan[], lineIndex: number) => lineIndex.toString())
        }
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
        }, (sp: RichSpan, index: number) => index.toString())
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
        }, (child: RenderBlock, index: number) => index.toString())
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
        }, (child: RenderBlock, index: number) => index.toString())
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  // ---------- 表格 ----------

  @Builder
  private TableBlock(block: RenderBlock) {
    Column() {
      Grid() {
        ForEach(block.tableRows, (row: TableCell[], rowIndex: number) => {
          ForEach(row, (cell: TableCell, colIndex: number) => {
            GridItem() {
              Column() {
                Text() {
                  ForEach(this.cellSpans(cell), (sp: RichSpan) => {
                    Span(sp.text)
                      .fontSize(sp.fontSize ?? this.config.bodyFontSize)
                      .fontWeight(sp.fontWeight ?? 400)
                      .fontStyle(toArkFontStyle(sp.fontStyle))
                      .decoration({ type: toArkDeco(sp.decoration), color: sp.decorationColor })
                      .fontColor(sp.color ?? this.config.tableTextColor)
                      .backgroundColor(sp.backgroundColor ?? '#00000000')
                  }, (sp: RichSpan, index: number) => index.toString())
                }
                .lineHeight(this.config.bodyFontSize * 1.5)
                .width('100%')
              }
              .padding(this.config.tableCellPadding)
              .backgroundColor(cell.isHeader ? this.config.tableHeaderBackground : Color.White)
              .alignItems(HorizontalAlign.Start)
            }
            .columnStart(colIndex)
            .columnEnd(colIndex + cell.colSpan - 1)
            .rowStart(rowIndex)
            .rowEnd(rowIndex + cell.rowSpan - 1)
          }, (cell: TableCell, colIndex: number) => rowIndex.toString() + '-' + colIndex.toString())
        }, (row: TableCell[], rowIndex: number) => rowIndex.toString())
      }
      .columnsTemplate(this.gridTemplate(block.tableCols))
      .rowsGap(1)
      .columnsGap(1)
      .backgroundColor(this.config.tableBorderColor)
      .width('100%')
    }
    .width('100%')
    .clip(true)
    .borderRadius(4)
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
