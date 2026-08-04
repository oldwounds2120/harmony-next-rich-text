/**
 * Index.ets - 组件源码统一导出
 * 包外使用：import { HtmlRichText, RichTextConfig } from 'htmlrichtext';
 *           （由仓库根目录 Index.ets 转发到这里）
 *
 * 目录约定：
 *   components/  - UI 组件（HtmlRichText 主组件、ImagePreviewDialog 图片预览）
 *   core/        - 纯逻辑（解析器、构建器、模型、配置、代码高亮）
 */
export { HtmlRichText } from './components/HtmlRichText';
export { ImagePreviewDialog } from './components/ImagePreviewDialog';
export { RichTextConfig } from './core/RichTextConfig';
export { HtmlParser } from './core/HtmlParser';
export { RichTextBuilder } from './core/RichTextBuilder';
export {
  NodeType, DisplayType, DecorationStyle, AlignStyle, FontStyleType,
  RichNode, RichStyle, RichSpan, InlineGroup, TableCell, RenderBlock
} from './core/RichTextModels';
