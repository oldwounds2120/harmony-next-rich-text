/**
 * RichTextConfig.ets
 * 富文本组件样式配置 - 所有可定制项集中于此
 * 传入组件：RichText({ html: '...', config: new RichTextConfig() })
 */
export class RichTextConfig {
  // ===== 正文 =====
  bodyFontFamily: string = 'HarmonyOS Sans'
  bodyFontSize: number = 16
  bodyColor: string = '#2B2B2B'
  bodyLineHeight: number = 1.7                 // 倍数
  paragraphSpacing: number = 12                // 段间距(vp)

  // ===== 标题 h1 ~ h6 =====
  headingSizes: number[] = [24, 21, 19, 17, 16, 15]
  headingWeights: number[] = [700, 700, 700, 700, 600, 600]
  headingColors: string[] = ['#1A1A1A', '#1A1A1A', '#1A1A1A', '#333333', '#333333', '#333333']
  headingMarginTop: number = 18
  headingMarginBottom: number = 8

  // ===== 链接 =====
  linkColor: string = '#1E6FFF'
  linkUnderline: boolean = true

  // ===== 代码 =====
  codeFontFamily: string = 'HarmonyOS Sans Mono'
  inlineCodeColor: string = '#D6336C'
  inlineCodeBackground: string = '#F3F4F6'
  codeBlockBackground: string = '#F6F8FA'
  codeBlockTextColor: string = '#24292F'
  codeBlockFontSize: number = 13
  codeBlockLineHeight: number = 1.6            // 倍数
  codeBlockRadius: number = 8
  codeBlockPadding: number = 12
  enableCodeHighlight: boolean = true

  // ===== 引用块 =====
  quoteBackground: string = '#F7F8FA'
  quoteBorderColor: string = '#C9D1D9'
  quoteTextColor: string = '#57606A'
  quotePadding: number = 12
  quoteMarginTop: number = 8
  quoteMarginBottom: number = 8

  // ===== 列表 =====
  listMarkerColor: string = '#2B2B2B'
  listIndent: number = 18
  listSpacing: number = 8
  listItemSpacing: number = 4

  // ===== 分割线 =====
  hrColor: string = '#E5E6EB'
  hrMargin: number = 16

  // ===== 表格 =====
  tableBorderColor: string = '#E5E6EB'
  tableHeaderBackground: string = '#F5F6F7'
  tableTextColor: string = '#2B2B2B'
  tableCellPadding: number = 8
  tableHeaderTextColor: string = '#1A1A1A'     // 表头文字颜色
  tableHeaderTextWeight: number = 600          // 表头文字字重
  tableEvenRowBackground: string = '#FFFFFF'   // 偶数数据行背景（与 tableOddRowBackground 配合做斑马纹，默认同色=无斑马纹）
  tableOddRowBackground: string = '#FFFFFF'    // 奇数数据行背景
  tableMinRowHeight: number = 0                // 最小行高(vp)，0 = 不设下限（行高测量结果与该值取大）

  // ===== 图片 =====
  imageRadius: number = 4
  imageMargin: number = 10
  imageInlineMargin: number = 6
  imagePlaceholderColor: string = '#F0F0F0'
  enableImagePreview: boolean = true

  /**
   * 大图判定比例（0~1）：图片 HTML 声明的宽度 ≥ 屏幕宽度 × 该比例 → 视为正文大图，
   * 移动端自适应铺满（等同 CSS width:100%; height:auto），忽略 PC 编辑器设置的固定宽高；
   * 低于该比例 → 视为小图/图标/表情，保持属性尺寸不放大。
   */
  largeImageRatio: number = 0.6
}
