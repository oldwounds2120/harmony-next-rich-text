/**
 * Index.ets - 包级统一入口（oh-package.json5 的 main 指向本文件）
 *
 * 安装为 ohpm 三方库后：
 *   import { HtmlRichText, RichTextConfig } from 'htmlrichtext';
 *
 * 源码方式使用（复制到工程）：
 *   import { HtmlRichText, RichTextConfig } from '../src/main/ets/htmlrichtext/Index';
 */
export { HtmlRichText } from './src/main/ets/htmlrichtext/Index';
export { RichTextConfig } from './src/main/ets/htmlrichtext/Index';
export { ImagePreviewDialog } from './src/main/ets/htmlrichtext/Index';
export { HtmlParser } from './src/main/ets/htmlrichtext/Index';
export { RichTextBuilder } from './src/main/ets/htmlrichtext/Index';
export {
  NodeType, DisplayType, DecorationStyle, AlignStyle, FontStyleType,
  RichNode, RichStyle, RichSpan, InlineGroup, TableCell, RenderBlock
} from './src/main/ets/htmlrichtext/Index';
