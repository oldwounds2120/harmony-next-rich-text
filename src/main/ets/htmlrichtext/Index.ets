/**
 * Index.ets - 组件源码统一导出
 * 包外使用：import { HtmlRichText, RichTextConfig } from 'htmlrichtext';
 *           （由仓库根目录 Index.ets 转发到这里）
 */
export { HtmlRichText } from './HtmlRichText';
export { RichTextConfig } from './RichTextConfig';
export { ImagePreviewDialog } from './ImagePreviewDialog';
export { HtmlParser } from './HtmlParser';
export { RichTextBuilder } from './RichTextBuilder';
export {
  NodeType, DisplayType, DecorationStyle, AlignStyle, FontStyleType,
  RichNode, RichStyle, RichSpan, InlineGroup, TableCell, RenderBlock
} from './RichTextModels';
