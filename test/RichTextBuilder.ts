/**
 * RichTextBuilder.ets
 * 渲染树构建器（纯逻辑层，可单测）
 * 职责：
 *  1. 遍历解析树，按标签与内联 CSS 计算继承样式
 *  2. 把行内内容"摊平"为 InlineGroup[]（文本连片合并，图片/链接独立成组）
 *  3. 生成扁平 RenderBlock[] 渲染模型
 * 关键设计：连续文本合并进一个 Text（多 Span），保证换行连续性；
 *           图片/链接作为独立 Flex 子项，保证可点击、可加载。
 */
import {
  RichNode, NodeType, RichStyle, RichSpan, InlineGroup, RenderBlock, TableCell,
  AlignStyle, DecorationStyle, FontStyleType
} from './RichTextModels.ts';
import { RichTextConfig } from './RichTextConfig.ts';
import { SimpleCodeHighlighter } from './SimpleCodeHighlighter.ts';

const NAMED_COLORS: Map<string, string> = new Map<string, string>([
  ['black', '#000000'], ['white', '#ffffff'], ['red', '#ff0000'], ['green', '#008000'],
  ['blue', '#0000ff'], ['yellow', '#ffff00'], ['orange', '#ffa500'], ['purple', '#800080'],
  ['gray', '#808080'], ['grey', '#808080'], ['silver', '#c0c0c0'], ['maroon', '#800000'],
  ['olive', '#808000'], ['lime', '#00ff00'], ['aqua', '#00ffff'], ['teal', '#008080'],
  ['navy', '#000080'], ['fuchsia', '#ff00ff'], ['pink', '#ffc0cb'], ['brown', '#a52a2a'],
  ['transparent', '#00000000'], ['darkgray', '#a9a9a9'], ['darkgrey', '#a9a9a9'],
  ['lightgray', '#d3d3d3'], ['lightgrey', '#d3d3d3'], ['gold', '#ffd700'],
  ['indigo', '#4b0082'], ['violet', '#ee82ee'], ['cyan', '#00ffff'], ['magenta', '#ff00ff']
]);

/**
 * 解析 CSS 颜色字符串为统一格式（组件层再映射为 ResourceColor）。
 * 支持：#rgb / #rrggbb / #rrggbbaa、rgb()、rgba()、常用英文色名（见 NAMED_COLORS）。
 * 解析失败返回 undefined（调用方忽略该样式，不抛错）。
 */
function parseColor(v: string): string | undefined {
  const s: string = v.trim().toLowerCase();
  if (s.length === 0) {
    return undefined;
  }
  if (s.startsWith('#')) {
    if (/^#[0-9a-f]{3}$/.test(s)) {
      // 3 位简写 #abc → 展开为 #aabbcc
      return '#' + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2) + s.charAt(3) + s.charAt(3);
    }
    if (/^#[0-9a-f]{6}$/.test(s) || /^#[0-9a-f]{8}$/.test(s)) {
      return s;
    }
    return undefined;
  }
  if (s.startsWith('rgb(')) {
    const m: RegExpMatchArray | null = s.match(/rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/);
    if (m !== null) {
      return toHex(Number(m[1]), Number(m[2]), Number(m[3]));
    }
    return undefined;
  }
  if (s.startsWith('rgba(')) {
    const m: RegExpMatchArray | null = s.match(/rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)/);
    if (m !== null) {
      return toHex(Number(m[1]), Number(m[2]), Number(m[3]), Math.round(parseFloat(m[4]) * 255));
    }
    return undefined;
  }
  return NAMED_COLORS.get(s);
}

/** RGB(A) → #rrggbb 或 #rrggbbaa（alpha 为 255 时省略 alpha 段） */
function toHex(r: number, g: number, b: number, a?: number): string {
  const h = (n: number): string => n.toString(16).padStart(2, '0');
  if (a !== undefined && a < 255) {
    return '#' + h(r) + h(g) + h(b) + h(a);
  }
  return '#' + h(r) + h(g) + h(b);
}

/** 解析 CSS font-weight（bold=700 / bolder=800 / lighter=300 / normal=400 / 100-900 数字） */
function parseFontWeight(v: string): number | undefined {
  const s: string = v.trim().toLowerCase();
  if (s === 'bold') {
    return 700;
  }
  if (s === 'bolder') {
    return 800;
  }
  if (s === 'lighter') {
    return 300;
  }
  if (s === 'normal') {
    return 400;
  }
  const n: number = parseInt(s, 10);
  if (!Number.isNaN(n) && n >= 100 && n <= 900) {
    return n;
  }
  return undefined;
}

/** 解析 CSS text-align 为内部 AlignStyle 枚举 */
function parseAlign(v: string): AlignStyle {
  const s: string = v.trim().toLowerCase();
  if (s === 'center') {
    return AlignStyle.CENTER;
  }
  if (s === 'right') {
    return AlignStyle.END;
  }
  if (s === 'justify') {
    return AlignStyle.JUSTIFY;
  }
  return AlignStyle.START;
}

/**
 * 解析 CSS line-height：返回"倍数"（组件层乘以字号得到 vp 值）。
 *  - 无单位数字（1.5）→ 直接作为倍数
 *  - 带 px（20px）→ 除以正文字号换算成倍数
 *  - normal / 空 → undefined（沿用父级行高）
 */
function parseLineHeight(v: string, bodyFontSize: number): number | undefined {
  const s: string = v.trim().toLowerCase();
  if (s === 'normal' || s.length === 0) {
    return undefined;
  }
  const n: number = parseFloat(s);
  if (Number.isNaN(n)) {
    return undefined;
  }
  if (s.endsWith('px')) {
    return n / bodyFontSize;
  }
  return n; // 无单位倍数
}

const INLINE_TAGS: Set<string> = new Set<string>([
  'span', 'strong', 'b', 'em', 'i', 'u', 'ins', 's', 'del', 'strike', 'a', 'code', 'kbd',
  'samp', 'tt', 'mark', 'sub', 'sup', 'small', 'big', 'abbr', 'q', 'label', 'cite',
  'var', 'dfn', 'font', 'bdi', 'bdo', 'time', 'data'
]);

export class RichTextBuilder {
  private config: RichTextConfig
  private baseUrl: string
  private root: RichNode
  private blocks: RenderBlock[] = []
  private listStack: string[] = []       // 'disc' | 'decimal'
  private listCounters: number[] = []
  private imageIndex: number = 0

  constructor(root: RichNode, config: RichTextConfig, baseUrl: string = '') {
    this.config = config;
    this.baseUrl = baseUrl;
    this.root = root;
    // 对根节点先计算一次基础样式（正文兜底）
    root.style = new RichStyle();
    root.style.fontSize = config.bodyFontSize;
    root.style.color = config.bodyColor;
    root.style.lineHeight = config.bodyLineHeight;
  }

  /** 生成渲染模型 */
  build(): RenderBlock[] {
    this.blocks = [];
    this.listStack = [];
    this.listCounters = [];
    this.imageIndex = 0;
    this.walkBlock(this.blocks, this.root, this.root.style);
    return this.blocks;
  }

  // ================= 块级遍历 =================

  /**
   * 块级节点遍历（渲染树构建的核心分发逻辑）。
   *
   * 对每个子节点按标签类别分发：
   *  - 文本节点         → 直接生成文本块（裸文本按段落处理）
   *  - p/div/section 等 → processContainer：内部行内内容合并成段、块级子标签分段递归
   *  - h1~h6           → 标题块（flattenInline 摊平行内内容）
   *  - blockquote      → 引用块（内部再走一遍 walkBlock）
   *  - ul/ol           → 列表（walkList 维护嵌套层级与序号）
   *  - pre             → 代码块（保留空白 + 语法高亮）
   *  - table           → 表格（解析 tr/td/th 与 colspan/rowspan）
   *  - hr/img          → 分割线 / 图片块
   *  - 其他 inline 标签 → 按段落文本处理（如顶层裸 <span>xx</span>）
   *
   * 样式通过 parentStyle 参数沿树向下继承（见 computeStyle）。
   */
  private walkBlock(out: RenderBlock[], node: RichNode, parentStyle: RichStyle): void {
    for (const child of node.children) {
      if (child.type === NodeType.TEXT) {
        const trimmed: string = child.text.trim();
        if (trimmed.length > 0) {
          this.pushTextBlock(out, child, parentStyle);
        }
        continue;
      }
      const style: RichStyle = this.computeStyle(child, parentStyle);
      this.processBlock(out, child, style);
    }
  }

  /**
   * 单个块级节点 → 生成渲染块（walkBlock 的遍历分发逻辑，独立出来供
   * processContainer 复用：容器（div 等）内的块级子标签必须走这里，否则
   * 直接遍历其子节点会让 table/h2/pre/ul/hr/img 等"自身即块"的标签
   * 落入兜底分支，退化成普通文本或丢失）。
   */
  private processBlock(out: RenderBlock[], child: RichNode, style: RichStyle): void {
    const tag: string = child.tag;
    if (tag === 'p' || tag === 'div' || tag === 'section' || tag === 'article' || tag === 'main'
      || tag === 'header' || tag === 'footer' || tag === 'aside' || tag === 'nav'
      || tag === 'figure' || tag === 'figcaption' || tag === 'center' || tag === 'address'
      || tag === 'form' || tag === 'details' || tag === 'summary') {
      this.processContainer(out, child, style);
    } else if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
      this.pushHeading(out, child, style, Number(tag.charAt(1)));
    } else if (tag === 'blockquote') {
      this.pushQuote(out, child, style);
    } else if (tag === 'ul' || tag === 'ol') {
      const listBlocks: RenderBlock[] = this.walkList(child, style);
      for (const b of listBlocks) {
        out.push(b);
      }
    } else if (tag === 'pre') {
      this.pushCode(out, child, style);
    } else if (tag === 'table') {
      this.pushTable(out, child, style);
    } else if (tag === 'hr') {
      this.pushHr(out, style);
    } else if (tag === 'img') {
      this.pushImage(out, child, style);
    } else {
      // 其他 inline 标签直接出现在块级位置：按段落处理
      this.pushTextBlock(out, child, style);
    }
  }

  /** 单个行内节点（或裸文本）直接生成一个文本块：用于块级位置的 span/strong/裸文本等 */
  private pushTextBlock(out: RenderBlock[], node: RichNode, style: RichStyle): void {
    const groups: InlineGroup[] = this.flattenInline([node], style);
    if (groups.length === 0) {
      return;
    }
    out.push(this.makeTextBlock(groups, style));
  }

  /**
   * 处理块容器（p/div/section 等）：
   * 连续的行内内容合并为一个文本块（保证换行连续），块级子标签分段递归
   */
  private processContainer(out: RenderBlock[], node: RichNode, style: RichStyle): void {
    // 为什么用"暂存 + 刷出"模式？
    // HTML 中 <p>一段<b>加粗</b>文字</p> 的"一段""加粗""文字"是三个节点，
    // 若各自成块会导致每段独立换行、英文单词被拦腰截断。
    // 所以先把连续的行内节点累积到 pending，一次性 flattenInline 成单个
    // Text（多 Span），保证整段文字的自然换行；遇到块级子标签（如 <p> 里嵌 <div>）
    // 则先刷出已累积的文本段，再递归处理该块。
    const pending: RichNode[] = [];
    const flush = (): void => {
      if (pending.length > 0) {
        const groups: InlineGroup[] = this.flattenInline(pending, style);
        pending.length = 0;
        if (groups.length > 0) {
          out.push(this.makeTextBlock(groups, style));
        }
      }
    };
    for (const child of node.children) {
      if (child.type === NodeType.TEXT) {
        if (child.text.trim().length > 0) {
          pending.push(child);
        }
        continue;
      }
      if (this.isBlockTag(child.tag)) {
        flush();
        this.processBlock(out, child, style);
      } else {
        pending.push(child);
      }
    }
    flush();
  }

  /** 判断是否为块级标签（用于 processContainer 分段；img/br 等行内元素不在此列） */
  private isBlockTag(tag: string): boolean {
    return tag === 'p' || tag === 'div' || tag === 'section' || tag === 'article' || tag === 'main'
      || tag === 'header' || tag === 'footer' || tag === 'aside' || tag === 'nav'
      || tag === 'figure' || tag === 'figcaption' || tag === 'center' || tag === 'address'
      || tag === 'form' || tag === 'details' || tag === 'summary' || tag === 'ul' || tag === 'ol'
      || tag === 'li' || tag === 'blockquote' || tag === 'pre' || tag === 'table' || tag === 'hr'
      || tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6';
  }

  /** 标题块：摊平行内内容生成文本块，标记 kind=heading 与级别（字号/字重由 computeStyle 已设置） */
  private pushHeading(out: RenderBlock[], node: RichNode, style: RichStyle, level: number): void {
    const groups: InlineGroup[] = this.flattenInline(node.children, style);
    if (groups.length === 0) {
      return;
    }
    const block: RenderBlock = this.makeTextBlock(groups, style);
    block.kind = 'heading';
    block.headingLevel = level;
    out.push(block);
  }

  /** 引用块：内部内容递归走一遍 walkBlock（通常是多个 p），打包成带左右边距的 quote 块 */
  private pushQuote(out: RenderBlock[], node: RichNode, style: RichStyle): void {
    const inner: RenderBlock[] = [];
    this.walkBlock(inner, node, style);
    const block: RenderBlock = new RenderBlock();
    block.kind = 'quote';
    block.children = inner;
    // 首块顶部、末块底部贴齐引用背景，避免段间距落在背景内部造成多余空白；
    // 中间块保留间距作为块间分隔（与 walkListItem 的边距压缩行为一致）
    if (inner.length > 0) {
      inner[0].marginTop = 0;
      inner[inner.length - 1].marginBottom = 0;
    }
    block.marginTop = this.config.quoteMarginTop;
    block.marginBottom = this.config.quoteMarginBottom;
    out.push(block);
  }

  /** 代码块：拼接 pre 内全部文本（保留换行）、去掉首尾多余空行、识别语言并做逐行高亮 */
  private pushCode(out: RenderBlock[], node: RichNode, style: RichStyle): void {
    let text: string = this.collectText(node);
    text = text.replace(/^\n+/, '').replace(/\n+$/, '');
    const block: RenderBlock = new RenderBlock();
    block.kind = 'code';
    block.codeLang = this.extractLang(node);
    block.codeLinesTokens = this.buildCodeTokens(text);
    block.marginTop = style.marginTop ?? this.config.paragraphSpacing;
    block.marginBottom = style.marginBottom ?? this.config.paragraphSpacing;
    out.push(block);
  }

  /** 分割线块：1px 横线 */
  private pushHr(out: RenderBlock[], style: RichStyle): void {
    const block: RenderBlock = new RenderBlock();
    block.kind = 'hr';
    block.marginTop = this.config.hrMargin;
    block.marginBottom = this.config.hrMargin;
    out.push(block);
  }

  /** 块级图片：解析 src（可拼接 baseUrl）、width/height 属性，并分配全文图片序号（供预览索引） */
  private pushImage(out: RenderBlock[], node: RichNode, style: RichStyle): void {
    // 图片 src 允许 data:/file:（base64 图等），其余协议被 resolveUrl 白名单过滤
    const src: string = this.resolveUrl(node.attrs.get('src') ?? '', true);
    if (src.length === 0) {
      return;
    }
    const block: RenderBlock = new RenderBlock();
    block.kind = 'image';
    block.imageSrc = src;
    block.imageAlt = node.attrs.get('alt') ?? '';
    block.imageWidth = this.parseLen(node.attrs.get('width') ?? (style.width ?? undefined));
    block.imageHeight = this.parseLen(node.attrs.get('height') ?? (style.height ?? undefined));
    block.imageIndex = this.imageIndex;
    this.imageIndex += 1;
    block.marginTop = this.config.imageMargin;
    block.marginBottom = this.config.imageMargin;
    out.push(block);
  }

  /** 表格：解析 tr → td/th（单元格内容摊平、colspan/rowspan/align），统计最大列数供 Grid 模板 */
  private pushTable(out: RenderBlock[], node: RichNode, style: RichStyle): void {
    const block: RenderBlock = new RenderBlock();
    block.kind = 'table';
    block.marginTop = style.marginTop ?? this.config.paragraphSpacing;
    block.marginBottom = style.marginBottom ?? this.config.paragraphSpacing;
    let maxCols: number = 0;
    // 行可能被 thead/tbody/tfoot 等容器包裹（如 <table><tbody><tr>…</tr></tbody></table>），
    // 需递归下钻容器收集 tr；但不进入 td/th，避免把单元格内嵌套表格的行错误收集进来
    const rows: RichNode[] = this.collectTableRows(node);
    for (const tr of rows) {
      const row: TableCell[] = [];
      for (const cellNode of tr.children) {
        if (cellNode.tag !== 'td' && cellNode.tag !== 'th') {
          continue;
        }
        const cell: TableCell = new TableCell();
        cell.isHeader = cellNode.tag === 'th';
        cell.groups = this.flattenInline(cellNode.children, style);
        const csAttr: string | undefined = cellNode.attrs.get('colspan');
        cell.colSpan = csAttr !== undefined ? (parseInt(csAttr, 10) || 1) : 1;
        const rsAttr: string | undefined = cellNode.attrs.get('rowspan');
        cell.rowSpan = rsAttr !== undefined ? (parseInt(rsAttr, 10) || 1) : 1;
        const alignAttr: string | undefined = cellNode.attrs.get('align');
        cell.align = alignAttr !== undefined ? parseAlign(alignAttr) : AlignStyle.START;
        row.push(cell);
      }
      // 列数按 colspan 展开后取最大（支持 <td colspan="2"> 跨列单元格的表格）
      let colCount: number = 0;
      for (const c of row) {
        colCount += c.colSpan;
      }
      if (colCount > maxCols) {
        maxCols = colCount;
      }
      block.tableRows.push(row);
    }
    block.tableCols = maxCols;
    if (block.tableRows.length > 0) {
      out.push(block);
    }
  }

  /**
   * 递归收集 table 下的所有 tr（穿透 thead/tbody/tfoot/caption 等容器标签），
   * 遇到 td/th 停止下钻（单元格内部视为行内内容，嵌套表格由外层独立解析）。
   */
  private collectTableRows(node: RichNode): RichNode[] {
    const rows: RichNode[] = [];
    const walk = (n: RichNode): void => {
      for (const c of n.children) {
        if (c.type !== NodeType.ELEMENT) {
          continue;
        }
        if (c.tag === 'tr') {
          rows.push(c);
        } else if (c.tag !== 'td' && c.tag !== 'th') {
          walk(c);
        }
      }
    };
    walk(node);
    return rows;
  }

  // ================= 列表 =================

  /**
   * 遍历 ul/ol：维护"列表类型栈"与"序号栈"，支持任意层级嵌套。
   *  - listStack    记录每层的类型（disc 圆点 / decimal 数字），决定 marker 样式
   *  - listCounters 记录每层有序列表的当前序号（从 0 起，li 时自增）
   * 返回该列表生成的所有 RenderBlock（顶层 li 会 push 到 out）
   */
  private walkList(node: RichNode, parentStyle: RichStyle): RenderBlock[] {
    const result: RenderBlock[] = [];
    const kind: string = node.tag === 'ol' ? 'decimal' : 'disc';
    this.listStack.push(kind);
    this.listCounters.push(0);
    const level: number = this.listStack.length;
    for (let i = 0; i < node.children.length; i++) {
      const child: RichNode = node.children[i];
      if (child.tag === 'li') {
        this.walkListItem(result, child, parentStyle, kind, level, i === 0);
      } else {
        this.walkBlock(result, child, parentStyle);
      }
    }
    this.listStack.pop();
    this.listCounters.pop();
    return result;
  }

  /**
   * 处理单个 li：
   *  - 计算 marker（有序：递增序号；无序：按层级 1/2/3+ 用 •/○/▪）
   *  - 内容拆分为两部分：普通行内内容 → 合并成一个文本块（children[0]）；
   *    嵌套的 ul/ol → 递归 walkList，生成子列表块挂到 children
   *  - listLevel / paddingLeft 用于逐级缩进
   */
  private walkListItem(out: RenderBlock[], node: RichNode, parentStyle: RichStyle,
    kind: string, level: number, isFirst: boolean): void {
    if (kind === 'decimal') {
      this.listCounters[level - 1] = (this.listCounters[level - 1] ?? 0) + 1;
    }
    const counter: number = this.listCounters[level - 1] ?? 0;
    let marker: string = '•';
    if (kind === 'decimal') {
      marker = `${counter}.`;
    } else if (level === 2) {
      marker = '○';
    } else if (level >= 3) {
      marker = '▪';
    }
    const block: RenderBlock = new RenderBlock();
    block.kind = 'list-item';
    block.listMarker = marker;
    block.listLevel = level;
    block.paddingLeft = (level - 1) * this.config.listIndent;
    block.marginTop = isFirst ? this.config.listSpacing : 0;
    block.marginBottom = this.config.listItemSpacing;

    const contentNodes: RichNode[] = [];
    for (const c of node.children) {
      if (c.tag === 'ul' || c.tag === 'ol') {
        const nested: RenderBlock[] = this.walkList(c, parentStyle);
        for (const nb of nested) {
          block.children.push(nb);
        }
      } else {
        contentNodes.push(c);
      }
    }
    if (contentNodes.length > 0) {
      const groups: InlineGroup[] = this.flattenInline(contentNodes, parentStyle);
      if (groups.length > 0) {
        const inner: RenderBlock = this.makeTextBlock(groups, parentStyle);
        inner.marginTop = 0;
        inner.marginBottom = 0;
        block.children.push(inner);
      }
    }
    out.push(block);
  }

  // ================= 行内摊平 =================

  /**
   * 行内内容"摊平"（本项目最关键的布局决策）。
   *
   * ArkUI 中行内样式只能用 Span 表达（Span 不支持放图片、不支持点击），
   * 而 Text 才是换行连续的载体。因此：
   *  - 连续的文本/样式节点（文字、strong、em、code...）→ 累积成 RichSpan 列表，
   *    最终合并进一个 Text（多个 Span），保证整段文字自然换行、单词不被截断；
   *  - img  → 单独成组（InlineGroup.kind='image'），组件层渲染为独立 Image，
   *    可加载/点击预览，与文本用 Flex wrap 混排；
   *  - a    → 单独成组（kind='link'），组件层渲染为带 onClick 的 Text，
   *    实现链接可点击；
   *  - br   → 直接插入 '\n' 换行符（Text 原生支持），不额外成组。
   */
  private flattenInline(nodes: RichNode[], parentStyle: RichStyle): InlineGroup[] {
    const groups: InlineGroup[] = [];
    let spans: RichSpan[] = [];
    const flushSpans = (): void => {
      if (spans.length > 0) {
        const g: InlineGroup = new InlineGroup();
        g.kind = 'text';
        g.spans = spans;
        groups.push(g);
        spans = [];
      }
    };
    const walk = (list: RichNode[], style: RichStyle): void => {
      for (const n of list) {
        if (n.type === NodeType.TEXT) {
          if (n.text.length === 0) {
            continue;
          }
          spans.push(this.makeSpan(n.text, style));
          continue;
        }
        const s: RichStyle = this.computeStyle(n, style);
        if (n.tag === 'img') {
          flushSpans();
          groups.push(this.makeImageGroup(n, s));
        } else if (n.tag === 'a') {
          flushSpans();
          groups.push(this.makeLinkGroup(n, s));
        } else if (n.tag === 'br') {
          spans.push(this.makeSpan('\n', style));
        } else {
          walk(n.children, s);
        }
      }
    };
    walk(nodes, parentStyle);
    flushSpans();
    return groups;
  }

  /**
   * 把 RichStyle 转成最终渲染用的 RichSpan。
   * baselineOffset 处理：上标 sup → 向上偏移 +0.5em；下标 sub → 向下偏移 -0.25em，
   * 组件层通过 LengthMetrics.vp() 包装（API 12+ 参数类型）。
   */
  private makeSpan(text: string, style: RichStyle): RichSpan {
    const sp: RichSpan = new RichSpan();
    sp.text = text;
    sp.fontSize = style.fontSize ?? this.config.bodyFontSize;
    sp.color = style.color ?? this.config.bodyColor;
    sp.fontWeight = style.fontWeight;
    sp.fontStyle = style.fontStyle;
    sp.decoration = style.decoration;
    sp.decorationColor = style.decorationColor;
    sp.backgroundColor = style.backgroundColor;
    sp.fontFamily = style.fontFamily;
    sp.letterSpacing = style.letterSpacing;
    if (style.verticalAlign === 'super') {
      sp.baselineOffset = (style.fontSize ?? this.config.bodyFontSize) * 0.5;
    } else if (style.verticalAlign === 'sub') {
      sp.baselineOffset = -(style.fontSize ?? this.config.bodyFontSize) * 0.25;
    }
    return sp;
  }

  /** 生成行内图片组：解析 src/alt/width/height/圆角，组件层渲染为可点击预览的 Image */
  private makeImageGroup(node: RichNode, style: RichStyle): InlineGroup {
    const g: InlineGroup = new InlineGroup();
    g.kind = 'image';
    g.src = this.resolveUrl(node.attrs.get('src') ?? '', true);
    g.alt = node.attrs.get('alt') ?? '';
    g.width = this.parseLen(node.attrs.get('width') ?? (style.width ?? undefined));
    g.height = this.parseLen(node.attrs.get('height') ?? (style.height ?? undefined));
    g.borderRadius = style.borderRadius ?? this.config.imageRadius;
    return g;
  }

  /**
   * 生成链接组：用"链接专属样式"递归摊平 a 内部内容，
   * 强制链接色 + 下划线（可配置），组件层整组渲染为可点击 Text。
   */
  private makeLinkGroup(node: RichNode, style: RichStyle): InlineGroup {
    const linkStyle: RichStyle = new RichStyle();
    linkStyle.color = style.color ?? this.config.linkColor;
    linkStyle.fontSize = style.fontSize;
    linkStyle.fontWeight = style.fontWeight;
    linkStyle.fontStyle = style.fontStyle;
    linkStyle.lineHeight = style.lineHeight;
    linkStyle.letterSpacing = style.letterSpacing;
    linkStyle.fontFamily = style.fontFamily;
    linkStyle.backgroundColor = style.backgroundColor;
    if (this.config.linkUnderline) {
      linkStyle.decoration = DecorationStyle.UNDERLINE;
      linkStyle.decorationColor = style.color ?? this.config.linkColor;
    }
    const g: InlineGroup = new InlineGroup();
    g.kind = 'link';
    // 链接 href 只放行 http/https，javascript:/data:/file: 等协议被拦截（安全底线）
    g.href = this.resolveUrl(node.attrs.get('href') ?? '');
    g.spans = this.flattenInline(node.children, linkStyle).flatMap((sub: InlineGroup): RichSpan[] => sub.spans);
    return g;
  }

  /** 把 InlineGroup 组装成文本渲染块：行高按"倍数 × 字号"换算成 vp，边距/对齐取自样式 */
  private makeTextBlock(groups: InlineGroup[], style: RichStyle): RenderBlock {
    const block: RenderBlock = new RenderBlock();
    block.kind = 'text';
    block.groups = groups;
    const fontSize: number = style.fontSize ?? this.config.bodyFontSize;
    block.fontSize = fontSize;
    block.lineHeight = (style.lineHeight ?? this.config.bodyLineHeight) * fontSize;
    block.textAlign = style.textAlign ?? AlignStyle.START;
    block.marginTop = style.marginTop ?? 0;
    block.marginBottom = style.marginBottom ?? 0;
    return block;
  }

  // ================= 样式计算 =================

  /**
   * 计算节点样式（三层叠加，模拟浏览器 CSS 级联）：
   *  1. 继承父级样式（颜色/字号/行高/对齐等沿 DOM 树传递）
   *  2. 应用标签默认样式（h1~h6 字号、strong 加粗、em 斜体、a 链接色、
   *     code 等宽+底色、sub/sup 上下标、blockquote 引用色、p 段间距等）
   *  3. 解析内联 style 属性并覆盖（优先级最高，见 applyInlineStyle）
   * 注意：strong 取 Math.max(600, 父级字重) 保证嵌套加粗不回退；
   *       code 字号在父字号基础上 -1，sub/sup 额外 -2 并标记 verticalAlign。
   */
  private computeStyle(node: RichNode, parent: RichStyle): RichStyle {
    const s: RichStyle = new RichStyle();
    s.color = parent.color;
    s.fontSize = parent.fontSize;
    s.fontWeight = parent.fontWeight;
    s.fontStyle = parent.fontStyle;
    s.decoration = parent.decoration;
    s.decorationColor = parent.decorationColor;
    s.lineHeight = parent.lineHeight;
    s.letterSpacing = parent.letterSpacing;
    s.backgroundColor = parent.backgroundColor;
    s.fontFamily = parent.fontFamily;
    s.textAlign = parent.textAlign;
    s.marginTop = parent.marginTop;
    s.marginBottom = parent.marginBottom;
    s.verticalAlign = parent.verticalAlign;
    s.width = parent.width;
    s.height = parent.height;
    s.borderRadius = parent.borderRadius;

    const tag: string = node.tag;
    const bodySize: number = this.config.bodyFontSize;
    if (tag === 'p') {
      s.marginTop = 0;
      s.marginBottom = this.config.paragraphSpacing;
    } else if (tag === 'div' || tag === 'section' || tag === 'article') {
      s.marginTop = 0;
      s.marginBottom = 0;
    } else if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
      const lv: number = Number(tag.charAt(1));
      s.fontSize = this.config.headingSizes[lv - 1];
      s.fontWeight = this.config.headingWeights[lv - 1];
      s.color = this.config.headingColors[lv - 1];
      s.marginTop = this.config.headingMarginTop;
      s.marginBottom = this.config.headingMarginBottom;
      s.lineHeight = 1.4;
    } else if (tag === 'strong' || tag === 'b') {
      s.fontWeight = Math.max(600, parent.fontWeight ?? 400);
    } else if (tag === 'em' || tag === 'i' || tag === 'cite' || tag === 'var') {
      s.fontStyle = FontStyleType.ITALIC;
    } else if (tag === 'u' || tag === 'ins') {
      s.decoration = DecorationStyle.UNDERLINE;
    } else if (tag === 's' || tag === 'del' || tag === 'strike') {
      s.decoration = DecorationStyle.LINE_THROUGH;
    } else if (tag === 'a') {
      s.color = this.config.linkColor;
      if (this.config.linkUnderline) {
        s.decoration = DecorationStyle.UNDERLINE;
        s.decorationColor = this.config.linkColor;
      }
    } else if (tag === 'code' || tag === 'kbd' || tag === 'samp' || tag === 'tt') {
      s.fontFamily = this.config.codeFontFamily;
      s.fontSize = (parent.fontSize ?? bodySize) - 1;
      s.backgroundColor = this.config.inlineCodeBackground;
      s.color = this.config.inlineCodeColor;
    } else if (tag === 'mark') {
      s.backgroundColor = '#FFE58F';
    } else if (tag === 'sub' || tag === 'sup') {
      s.verticalAlign = tag === 'sub' ? 'sub' : 'super';
      s.fontSize = (parent.fontSize ?? bodySize) - 2;
    } else if (tag === 'small') {
      s.fontSize = (parent.fontSize ?? bodySize) - 2;
    } else if (tag === 'big') {
      s.fontSize = (parent.fontSize ?? bodySize) + 2;
    } else if (tag === 'blockquote') {
      s.color = this.config.quoteTextColor;
    } else if (tag === 'li') {
      s.marginTop = 0;
      s.marginBottom = 0;
    }

    const styleAttr: string | undefined = node.attrs.get('style');
    if (styleAttr !== undefined) {
      this.applyInlineStyle(styleAttr, s);
    }
    return s;
  }

  /**
   * 解析内联 style 属性（如 style="color:#f00;font-size:18px"）并覆盖到 RichStyle。
   * 逐条按 "key: value" 解析，支持 color/background/font-size/font-weight/
   * font-style/text-decoration/line-height/letter-spacing/text-align/
   * margin/padding/border-radius/vertical-align/width/height；
   * 解析失败或未知属性直接跳过（不抛错）。
   */
  private applyInlineStyle(styleStr: string, s: RichStyle): void {
    if (styleStr.length === 0) {
      return;
    }
    const segs: string[] = styleStr.split(';');
    for (const seg of segs) {
      const idx: number = seg.indexOf(':');
      if (idx < 0) {
        continue;
      }
      const key: string = seg.substring(0, idx).trim().toLowerCase();
      const value: string = seg.substring(idx + 1).trim();
      switch (key) {
        case 'color': {
          const c: string | undefined = parseColor(value);
          if (c !== undefined) {
            s.color = c;
          }
          break;
        }
        case 'background-color':
        case 'background': {
          const c: string | undefined = parseColor(value);
          if (c !== undefined) {
            s.backgroundColor = c;
          }
          break;
        }
        case 'font-size': {
          const f: number | undefined = this.parseLen(value);
          if (f !== undefined) {
            s.fontSize = f;
          }
          break;
        }
        case 'font-weight': {
          const w: number | undefined = parseFontWeight(value);
          if (w !== undefined) {
            s.fontWeight = w;
          }
          break;
        }
        case 'font-style':
          if (value === 'italic' || value === 'oblique') {
            s.fontStyle = FontStyleType.ITALIC;
          }
          break;
        case 'text-decoration':
          if (value.includes('underline')) {
            s.decoration = DecorationStyle.UNDERLINE;
          } else if (value.includes('line-through')) {
            s.decoration = DecorationStyle.LINE_THROUGH;
          }
          break;
        case 'line-height': {
          const l: number | undefined = parseLineHeight(value, this.config.bodyFontSize);
          if (l !== undefined) {
            s.lineHeight = l;
          }
          break;
        }
        case 'letter-spacing': {
          const l: number | undefined = this.parseLen(value);
          if (l !== undefined) {
            s.letterSpacing = l;
          }
          break;
        }
        case 'text-align':
          s.textAlign = parseAlign(value);
          break;
        case 'margin-top': {
          const m: number | undefined = this.parseLen(value);
          if (m !== undefined) {
            s.marginTop = m;
          }
          break;
        }
        case 'margin-bottom': {
          const m: number | undefined = this.parseLen(value);
          if (m !== undefined) {
            s.marginBottom = m;
          }
          break;
        }
        case 'padding-left': {
          const m: number | undefined = this.parseLen(value);
          if (m !== undefined) {
            s.paddingLeft = m;
          }
          break;
        }
        case 'padding-right': {
          const m: number | undefined = this.parseLen(value);
          if (m !== undefined) {
            s.paddingRight = m;
          }
          break;
        }
        case 'border-radius': {
          const r: number | undefined = this.parseLen(value);
          if (r !== undefined) {
            s.borderRadius = r;
          }
          break;
        }
        case 'font-family':
          s.fontFamily = value.replace(/['"]/g, '');
          break;
        case 'vertical-align':
          if (value === 'super') {
            s.verticalAlign = 'super';
          } else if (value === 'sub') {
            s.verticalAlign = 'sub';
          }
          break;
        case 'width':
          s.width = value;
          break;
        case 'height':
          s.height = value;
          break;
        default:
          break;
      }
    }
  }

  // ================= 工具 =================

  /** 递归收集节点子树内的全部文本（用于 pre 代码内容拼接，保留换行与空格） */
  private collectText(node: RichNode): string {
    let result: string = '';
    for (const c of node.children) {
      if (c.type === NodeType.TEXT) {
        result += c.text;
      } else {
        result += this.collectText(c);
      }
    }
    return result;
  }

  /** 识别代码语言：优先 <pre class="language-xxx">，其次 data-language，最后看子 <code> 的 class */
  private extractLang(node: RichNode): string {
    const cls: string = node.attrs.get('class') ?? '';
    const m: RegExpMatchArray | null = cls.match(/language-([a-zA-Z0-9_+-]+)/);
    if (m !== null) {
      return m[1].toLowerCase();
    }
    const dl: string | undefined = node.attrs.get('data-language');
    if (dl !== undefined && dl.length > 0) {
      return dl.toLowerCase();
    }
    for (const c of node.children) {
      if (c.tag === 'code') {
        const c2: string = c.attrs.get('class') ?? '';
        const m2: RegExpMatchArray | null = c2.match(/language-([a-zA-Z0-9_+-]+)/);
        if (m2 !== null) {
          return m2[1].toLowerCase();
        }
      }
    }
    return '';
  }

  /**
   * 代码文本 → 逐行高亮 token 列表（二维数组：行 → 带颜色的 RichSpan[]）。
   * 在构建阶段一次性算好，渲染时零计算。
   * 空格/tab 统一替换为不换行空格 \u00A0：保证每行不自动换行，
   * 超长行由组件层 Scroll 横向滚动（否则 Text 会断行破坏缩进对齐）。
   */
  private buildCodeTokens(text: string): RichSpan[][] {
    const lines: string[] = text.split('\n');
    const result: RichSpan[][] = [];
    for (const line of lines) {
      if (line.trim().length === 0) {
        result.push([]);
        continue;
      }
      let tokens: RichSpan[];
      if (this.config.enableCodeHighlight) {
        tokens = SimpleCodeHighlighter.highlight(line);
      } else {
        tokens = [this.makePlainSpan(line)];
      }
      // 空格转不换行空格：保证行不自动换行，超宽用横向滚动
      for (const t of tokens) {
        t.text = t.text.replace(/ /g, '\u00A0').replace(/\t/g, '\u00A0\u00A0\u00A0\u00A0');
      }
      result.push(tokens);
    }
    return result;
  }

  /** 无高亮模式下的纯文本 span（颜色留空，组件层回退到代码块默认色） */
  private makePlainSpan(text: string): RichSpan {
    const sp: RichSpan = new RichSpan();
    sp.text = text;
    sp.color = undefined;
    return sp;
  }

  /**
   * 解析长度字符串为 vp 数值：
   *  - 数字 / px / vp / rem → 原值；em → 字号倍数；pt → ×1.33
   *  - % / auto / 空 → undefined（交给组件层用 100% 或自适应处理）
   */
  private parseLen(v: string | undefined): number | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    const s: string = v.trim().toLowerCase();
    if (s.length === 0 || s === 'auto') {
      return undefined;
    }
    const num: number = parseFloat(s);
    if (Number.isNaN(num)) {
      return undefined;
    }
    if (s.endsWith('%')) {
      return undefined;
    }
    if (s.endsWith('em')) {
      return num * this.config.bodyFontSize;
    }
    if (s.endsWith('pt')) {
      return num * 1.33;
    }
    return num; // px / vp / 纯数字
  }

  /**
   * 图片/链接地址处理（含协议白名单，安全加固）：
   *  - 协议白名单：仅 http/https 始终放行；图片额外放行 data:/file:（base64 图合法），
   *    链接不放行 data:/file:；
   *  - javascript:/vbscript: 等伪协议一律拦截，返回空字符串（安全底线，防注入）；
   *  - 根路径 /xxx 或未提供 baseUrl 时原样返回；其余相对路径拼接 baseUrl 前缀。
   */
  private resolveUrl(src: string, allowDataFile: boolean = false): string {
    const lower: string = src.toLowerCase();
    if (lower.startsWith('javascript:') || lower.startsWith('vbscript:')) {
      return '';
    }
    if (src.startsWith('http://') || src.startsWith('https://')
      || src.startsWith('/') || this.baseUrl.length === 0) {
      return src;
    }
    if (lower.startsWith('data:') || lower.startsWith('file:')) {
      return allowDataFile ? src : '';
    }
    return this.baseUrl.replace(/\/$/, '') + '/' + src.replace(/^\//, '');
  }
}
