/**
 * run.ts - 纯逻辑层单测（Node 22+，无需 ArkUI 环境）
 * 运行方式见 README：将 .ets 复制为 .ts 后执行
 *   node --experimental-transform-types run.ts
 */
import { HtmlParser } from './HtmlParser.ts';
import { RichTextBuilder } from './RichTextBuilder.ts';
import { RichTextConfig } from './RichTextConfig.ts';
import { SimpleCodeHighlighter } from './SimpleCodeHighlighter.ts';
import { NodeType, RenderBlock, InlineGroup, RichSpan } from './RichTextModels.ts';

let passed = 0;
let failed = 0;

function assert(cond: boolean, msg: string): void {
  if (cond) {
    passed++;
    console.log(`  ✓ ${msg}`);
  } else {
    failed++;
    console.error(`  ✗ ${msg}`);
  }
}

function build(html: string): RenderBlock[] {
  const root = HtmlParser.parse(html);
  return new RichTextBuilder(root, new RichTextConfig(), '').build();
}

function textOf(blocks: RenderBlock[]): string {
  let out = '';
  const walk = (bs: RenderBlock[]): void => {
    for (const b of bs) {
      for (const g of b.groups) {
        for (const sp of g.spans) {
          out += sp.text;
        }
      }
      walk(b.children);
    }
  };
  walk(blocks);
  return out;
}

console.log('\n[1] HtmlParser 基础解析');
{
  const root = HtmlParser.parse('<p>Hello <strong>World</strong></p>');
  assert(root.children.length === 1, '根节点有一个子节点');
  const p = root.children[0];
  assert(p.tag === 'p', '子节点为 p 标签');
  assert(p.children.length === 2, 'p 有两个子节点');
  assert(p.children[0].text === 'Hello ', '第一个子节点文本为 "Hello "');
  assert(p.children[1].tag === 'strong', '第二个子节点为 strong');
}

console.log('\n[2] 实体解码');
{
  const root = HtmlParser.parse('<p>a&amp;b &lt;c&gt; &#39;x&#39; &#x41; &nbsp;end</p>');
  const text = root.children[0].children[0].text;
  assert(text === 'a&b <c> \'x\' A \u00A0end', '实体正确解码: ' + JSON.stringify(text));
}

console.log('\n[3] 属性解析与自闭合');
{
  const root = HtmlParser.parse('<img src="a.png" width="200" /><br><img src=\'b.png\'>');
  const img1 = root.children[0];
  assert(img1.tag === 'img' && img1.attrs.get('src') === 'a.png', '双引号属性解析');
  assert(img1.attrs.get('width') === '200', 'width 属性解析');
  const br = root.children[1];
  assert(br.tag === 'br', 'br 自闭合');
  const img2 = root.children[2];
  assert(img2.attrs.get('src') === 'b.png', '单引号属性解析');
}

console.log('\n[4] 容错：未闭合标签');
{
  const root = HtmlParser.parse('<div><p>abc');
  const div = root.children[0];
  assert(div.tag === 'div', 'div 为根子节点');
  const p = div.children[0];
  assert(p.tag === 'p', '未闭合 p 自动补全为 div 子节点');
  assert(p.children[0].text === 'abc', 'p 内容正确');
}

console.log('\n[5] 注释与 script 跳过');
{
  const root = HtmlParser.parse('<p>a<!-- comment -->b<script>var x=1;</script>c</p>');
  const text = root.children[0].children[0].text;
  assert(text === 'abc', '注释和 script 内容被跳过: ' + JSON.stringify(text));
}

console.log('\n[6] 文本渲染模型（样式继承）');
{
  const blocks = build('<p>今天<strong>很<em>棒</em></strong>！</p>');
  assert(blocks.length === 1, '生成一个 text 块');
  const groups = blocks[0].groups;
  assert(groups.length === 1 && groups[0].kind === 'text', '文本连片合并为单个 group');
  const spans = groups[0].spans;
  assert(spans.length === 4, '四个 span（正文/加粗/加粗斜体/正文）: ' + String(spans.length));
  assert(spans[0].fontWeight === undefined && spans[1].fontWeight === 600, 'strong 加粗继承(600)');
  assert(spans[2].fontStyle === 1, 'em 斜体生效');
}

console.log('\n[7] 链接与图片分组');
{
  const blocks = build('<p>点击<a href="/doc/1">这里</a>查看<img src="x.png">图片</p>');
  const groups = blocks[0].groups;
  assert(groups.length === 5, '分组为 text/link/text/image/text 共 5 组');
  const link = groups.find((g: InlineGroup) => g.kind === 'link');
  assert(link !== undefined && link.href === '/doc/1', '链接分组携带 href');
  const img = groups.find((g: InlineGroup) => g.kind === 'image');
  assert(img !== undefined && img.src === 'x.png', '图片分组携带 src');
}

console.log('\n[8] 列表与嵌套');
{
  const blocks = build('<ul><li>甲<ul><li>乙1</li><li>乙2</li></ul></li><li>丙</li></ul>');
  const first = blocks[0];
  assert(first.kind === 'list-item' && first.listMarker === '•', '一级列表 marker 为圆点');
  assert(first.listLevel === 1, '一级层级=1');
  assert(first.children.length === 3, '嵌套列表生成子块（内容块 + 2 个二级项）: ' + String(first.children.length));
  const nested = first.children[1];
  assert(nested.kind === 'list-item' && nested.listMarker === '○', '二级列表 marker 为空心圆');
  const second = blocks[1];
  assert(second.kind === 'list-item' && second.listMarker === '•', '第二个一级项');
}

console.log('\n[9] 有序列表序号');
{
  const blocks = build('<ol><li>一</li><li>二</li><li>三</li></ol>');
  assert(blocks[0].listMarker === '1.', '第一项为 1.');
  assert(blocks[1].listMarker === '2.', '第二项为 2.');
  assert(blocks[2].listMarker === '3.', '第三项为 3.');
}

console.log('\n[10] 引用块与代码块');
{
  const blocks = build('<blockquote><p>引用文字</p></blockquote><pre><code>const a = 1; // 注释</code></pre>');
  assert(blocks[0].kind === 'quote', '引用块生成');
  assert(blocks[0].children[0].groups.length > 0, '引用块内部有文本');
  assert(blocks[1].kind === 'code', '代码块生成');
  const tokens: RichSpan[][] = blocks[1].codeLinesTokens;
  assert(tokens.length === 1, '代码块拆分为一行');
  const lineText = tokens[0].map((s: RichSpan) => s.text).join('');
  assert(lineText.includes('const'), '代码内容保留: ' + JSON.stringify(lineText));
  assert(tokens[0].some((s: RichSpan) => s.color === '#6A737D'), '注释被高亮为注释色');
}

console.log('\n[11] 表格');
{
  const blocks = build('<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>');
  assert(blocks[0].kind === 'table', '表格生成');
  assert(blocks[0].tableRows.length === 2, '两行');
  assert(blocks[0].tableCols === 2, '两列');
  assert(blocks[0].tableRows[0][0].isHeader === true, '表头识别');
  const cellGroups: InlineGroup[] = blocks[0].tableRows[1][0].groups;
  assert(cellGroups.length > 0 && cellGroups[0].spans[0].text === '1', '单元格内容正确');
}

console.log('\n[12] 标题与内联样式');
{
  const blocks = build('<h1 style="color:#ff0000;">红标题</h1><p style="font-size:20px;text-align:center;">居中</p>');
  assert(blocks[0].kind === 'heading' && blocks[0].headingLevel === 1, 'h1 标题块');
  const h1Spans = blocks[0].groups[0].spans;
  assert(h1Spans[0].color === '#ff0000', '内联 color 生效');
  assert(blocks[0].fontSize === 24, 'h1 默认字号 24');
  assert(blocks[1].groups[0].spans[0].fontSize === 20, '内联 font-size 生效');
  assert(blocks[1].textAlign === 1, 'text-align:center 生效');
}

console.log('\n[13] 代码高亮器');
{
  const tokens = SimpleCodeHighlighter.highlight('const x = "str"; // note');
  const joined = tokens.map((s: RichSpan) => s.text).join('|');
  assert(tokens.some((s: RichSpan) => s.color === '#CF222E'), '关键字被高亮');
  assert(tokens.some((s: RichSpan) => s.color === '#22863A'), '字符串被高亮');
  assert(tokens.some((s: RichSpan) => s.color === '#6A737D'), '注释被高亮');
  assert(joined.includes('const'), '内容不丢失');
}

console.log('\n[14] baseUrl 拼接');
{
  const root = HtmlParser.parse('<p><img src="img/a.png"></p>');
  const builder = new RichTextBuilder(root, new RichTextConfig(), 'https://cdn.x.com/static/');
  const blocks = builder.build();
  const g = blocks[0].groups.find((x: InlineGroup) => x.kind === 'image');
  assert(g !== undefined && g.src === 'https://cdn.x.com/static/img/a.png', '相对路径拼接正确');
}

console.log('\n[15] 复杂文档整体渲染');
{
  const html = '<h2>标题</h2><p>正文<strong>加粗</strong></p>' +
    '<blockquote><p>引用</p></blockquote>' +
    '<ul><li>列表1</li><li>列表2</li></ul>' +
    '<pre><code>fn main() {}</code></pre>' +
    '<table><tr><td>a</td><td>b</td></tr></table>';
  const blocks = build(html);
  assert(blocks.length === 7, '生成 7 个顶层块: ' + String(blocks.length));
  const kinds = blocks.map((b: RenderBlock) => b.kind).join(',');
  assert(kinds === 'heading,text,quote,list-item,list-item,code,table', '块类型顺序正确: ' + kinds);
}

console.log(`\n========================================`);
console.log(`结果：通过 ${passed}，失败 ${failed}`);
console.log(`========================================\n`);
process.exit(failed > 0 ? 1 : 0);
