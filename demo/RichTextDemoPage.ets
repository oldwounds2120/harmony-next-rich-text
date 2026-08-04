/**
 * RichTextDemoPage.ets - 使用示例（Demo）
 *
 * 使用方法：
 *  1. 把 RichTextComponent/src/main/ets/htmlrichtext 整个目录复制到你的工程
 *     entry/src/main/ets/htmlrichtext 下
 *  2. 复制本文件到 entry/src/main/ets/pages/RichTextDemoPage.ets
 *  3. 在 main_pages.json 中注册：{ "src": "pages/RichTextDemoPage" }
 *  4. 编译运行即可看到所有标签的渲染效果
 */
import { HtmlRichText, RichTextConfig } from '../htmlrichtext/Index';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

const DEMO_HTML: string = `
<h2>鸿蒙 NEXT 富文本组件 Demo</h2>
<p>这是一个<strong>自定义富文本组件</strong>，支持<em>斜体</em>、<u>下划线</u>、<del>删除线</del>、
<mark>高亮</mark>、行内<code>code</code>、上标 x<sup>2</sup>、下标 H<sub>2</sub>O，
以及<a href="https://www.harmonyos.com" style="color:#1E6FFF">超链接</a>。</p>
<p style="color:#FF6B00;font-size:18px;font-weight:bold;">这一行演示了内联 style：橙色、18号、加粗。</p>

<h3>图片（点击可全屏预览）</h3>
<figure>
  <img src="https://picsum.photos/seed/harmony/800/450" alt="示例图片 1" />
  <figcaption style="text-align:center;color:#888;font-size:13px;">图 1：picsum 占位图（可替换成你的图片地址）</figcaption>
</figure>

<h3>无序列表</h3>
<ul>
  <li>纯 ArkUI 原生渲染（Text + Span），不依赖 WebView</li>
  <li>样式通过 RichTextConfig 集中配置，灵活可控</li>
  <li>支持嵌套列表：
    <ul>
      <li>二级列表项 A</li>
      <li>二级列表项 B</li>
    </ul>
  </li>
</ul>

<h3>有序列表</h3>
<ol>
  <li>第一步：复制组件目录到工程</li>
  <li>第二步：在页面中引用 RichText</li>
  <li>第三步：传入 HTML 字符串</li>
</ol>

<h3>引用块</h3>
<blockquote>
  <p>路漫漫其修远兮，吾将上下而求索。</p>
  <p>—— 屈原《离骚》</p>
</blockquote>

<h3>代码块（支持轻量语法高亮、横向滚动）</h3>
<pre><code class="language-typescript">// 示例：ArkTS 代码
interface User {
  name: string;
  age: number;
}

function greet(user: User): string {
  const msg = \`Hello, \${user.name}!\`;
  console.log(msg); // 输出问候语
  return msg;
}
</code></pre>

<h3>表格</h3>
<table>
  <tr><th>框架</th><th>类型</th><th>性能</th></tr>
  <tr><td>Web</td><td>WebView 渲染</td><td>一般</td></tr>
  <tr><td>RichText</td><td>系统富文本</td><td>好但样式受限</td></tr>
  <tr><td><strong>本组件</strong></td><td>ArkUI 原生</td><td>好且完全可控</td></tr>
</table>

<hr />
<p style="text-align:center;color:#999;font-size:13px;">— 全文完 —</p>
`;

@Entry
@Component
struct RichTextDemoPage {
  @State html: string = DEMO_HTML
  private config: RichTextConfig = new RichTextConfig()
  private context = getContext(this) as common.UIAbilityContext

  private onLinkClick(url: string): void {
    console.info(`[RichTextDemo] 链接点击: ${url}`);
    // 方式一：用系统浏览器打开（推荐）
    try {
      this.context.openLink(url);
    } catch (e) {
      console.error(`[RichTextDemo] 打开链接失败: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: `链接：${url}` });
    }
  }

  private onImageClick(index: number, url: string): void {
    console.info(`[RichTextDemo] 图片点击 第${index}张: ${url}`);
  }

  private onImageLoadError(url: string): void {
    console.error(`[RichTextDemo] 图片加载失败: ${url}`);
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('富文本 Demo')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(48)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Color.White)

      // 正文区
      Scroll() {
        Column() {
          HtmlRichText({
            html: this.html,
            config: this.config,
            baseUrl: '',
            onLinkClick: (url: string) => this.onLinkClick(url),
            onImageClick: (index: number, url: string) => this.onImageClick(index, url),
            onImageLoadError: (url: string) => this.onImageLoadError(url)
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Auto)
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#F7F8FA')
    }
    .width('100%')
    .height('100%')
  }
}
