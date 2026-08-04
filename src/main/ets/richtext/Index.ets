/**
 * Index.ets - 组件统一导出
 * 页面中：import { RichText, RichTextConfig } from '../richtext/Index';
 */
export { RichText } from './RichText';
export { RichTextConfig } from './RichTextConfig';
export { ImagePreviewDialog } from './ImagePreviewDialog';
export { HtmlParser } from './HtmlParser';
export { RichTextBuilder } from './RichTextBuilder';
export {
  NodeType, DisplayType, DecorationStyle, AlignStyle, FontStyleType,
  RichNode, RichStyle, RichSpan, InlineGroup, TableCell, RenderBlock
} from './RichTextModels';
