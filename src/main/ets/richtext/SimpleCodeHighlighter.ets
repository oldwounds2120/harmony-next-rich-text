/**
 * SimpleCodeHighlighter.ets
 * 轻量语法高亮（纯逻辑层）—— 适用于资讯文章中分享的代码片段
 * 支持：行注释 // 与 #、块注释、字符串、数字、关键字、函数调用
 * 颜色使用 GitHub 风格，可通过 RichTextConfig.codeBlockTextColor 等覆盖
 */
import { RichSpan } from './RichTextModels';

export class SimpleCodeHighlighter {
  private static readonly COMMENT = '#6A737D'
  private static readonly STRING = '#22863A'
  private static readonly KEYWORD = '#CF222E'
  private static readonly NUMBER = '#0550AE'
  private static readonly FUNCTION = '#8250DF'
  private static readonly DEFAULT = '#24292F'

  private static readonly KEYWORDS: Set<string> = new Set<string>([
    // JS/TS
    'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'do',
    'switch', 'case', 'break', 'continue', 'new', 'class', 'extends', 'super', 'this',
    'import', 'from', 'export', 'default', 'try', 'catch', 'finally', 'throw', 'typeof',
    'instanceof', 'void', 'null', 'undefined', 'true', 'false', 'async', 'await', 'yield',
    'interface', 'type', 'enum', 'namespace', 'public', 'private', 'protected', 'static',
    'readonly', 'abstract', 'implements', 'in', 'of', 'as', 'is', 'keyof', 'satisfies',
    // Python
    'def', 'class', 'print', 'return', 'if', 'elif', 'else', 'for', 'while', 'import',
    'from', 'as', 'with', 'try', 'except', 'finally', 'raise', 'lambda', 'pass', 'del',
    'global', 'nonlocal', 'assert', 'yield', 'None', 'True', 'False', 'break', 'continue',
    'and', 'or', 'not', 'in', 'is',
    // C/Java 系
    'int', 'float', 'double', 'char', 'string', 'bool', 'boolean', 'long', 'short',
    'signed', 'unsigned', 'struct', 'union', 'typedef', 'volatile', 'register', 'extern',
    'goto', 'sizeof', 'main', 'void', 'include', 'define', 'ifdef', 'ifndef', 'endif',
    'package', 'import', 'final', 'synchronized', 'transient', 'native', 'throws',
    'throw', 'byte', 'switch', 'catch',
    // SQL
    'select', 'from', 'where', 'insert', 'update', 'delete', 'create', 'table', 'join',
    'inner', 'left', 'right', 'group', 'order', 'by', 'having', 'limit', 'values', 'into',
    'set', 'drop', 'alter', 'index', 'primary', 'key', 'foreign', 'references', 'distinct',
    'count', 'sum', 'avg', 'min', 'max', 'on', 'and', 'or', 'not', 'null',
    // 常见库函数名（避免被误标为普通文本，颜色统一按关键字处理）
    'require', 'module', 'exports', 'console', 'log'
  ]);

  /** 对单行代码做高亮，返回带颜色的 RichSpan[] */
  static highlight(code: string): RichSpan[] {
    const spans: RichSpan[] = [];
    const push = (text: string, color: string): void => {
      if (text.length === 0) {
        return;
      }
      const last: RichSpan | undefined = spans.length > 0 ? spans[spans.length - 1] : undefined;
      if (last !== undefined && last.color === color) {
        last.text += text;
        return;
      }
      const sp: RichSpan = new RichSpan();
      sp.text = text;
      sp.color = color;
      spans.push(sp);
    };

    const n: number = code.length;
    let i = 0;
    while (i < n) {
      const ch: string = code[i];
      const next: string = i + 1 < n ? code[i + 1] : '';

      // 行注释 // 
      if (ch === '/' && next === '/') {
        let j = code.indexOf('\n', i);
        j = j === -1 ? n : j;
        push(code.substring(i, j), SimpleCodeHighlighter.COMMENT);
        i = j;
        continue;
      }
      // 块注释 /* ... */
      if (ch === '/' && next === '*') {
        let j = code.indexOf('*/', i + 2);
        j = j === -1 ? n : j + 2;
        push(code.substring(i, j), SimpleCodeHighlighter.COMMENT);
        i = j;
        continue;
      }
      // 行注释 #（Python / shebang），仅当后跟字母或行尾
      if (ch === '#') {
        let j = code.indexOf('\n', i);
        j = j === -1 ? n : j;
        push(code.substring(i, j), SimpleCodeHighlighter.COMMENT);
        i = j;
        continue;
      }
      // 字符串（支持转义）
      if (ch === '"' || ch === "'" || ch === '`') {
        let j = i + 1;
        while (j < n) {
          if (code[j] === '\\') {
            j += 2;
            continue;
          }
          if (code[j] === ch) {
            j += 1;
            break;
          }
          j += 1;
        }
        push(code.substring(i, Math.min(j, n)), SimpleCodeHighlighter.STRING);
        i = j;
        continue;
      }
      // 数字（0x/0b/0o、小数、科学计数）
      if (SimpleCodeHighlighter.isDigit(ch) || (ch === '.' && SimpleCodeHighlighter.isDigit(next))) {
        let j = i;
        while (j < n) {
          const c: string = code[j];
          if (SimpleCodeHighlighter.isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
            || c === 'x' || c === 'X' || c === 'b' || c === 'B' || c === 'o' || c === 'O'
            || c === '_' || c === '.') {
            j += 1;
            continue;
          }
          if ((c === '+' || c === '-') && j > i && (code[j - 1] === 'e' || code[j - 1] === 'E')) {
            j += 1;
            continue;
          }
          if ((c === 'e' || c === 'E') && j + 1 < n && (SimpleCodeHighlighter.isDigit(code[j + 1]) || code[j + 1] === '+' || code[j + 1] === '-')) {
            j += 1;
            continue;
          }
          break;
        }
        push(code.substring(i, j), SimpleCodeHighlighter.NUMBER);
        i = j;
        continue;
      }
      // 单词 / 标识符
      if (SimpleCodeHighlighter.isWordStart(ch)) {
        let j = i;
        while (j < n && SimpleCodeHighlighter.isWordChar(code[j])) {
          j += 1;
        }
        const word: string = code.substring(i, j);
        // 函数调用：后跟 '(' 且非关键字
        let k = j;
        while (k < n && code[k] === ' ') {
          k += 1;
        }
        if (code[k] === '(' && !SimpleCodeHighlighter.KEYWORDS.has(word)) {
          push(word, SimpleCodeHighlighter.FUNCTION);
          i = j;
          continue;
        }
        push(word,
          SimpleCodeHighlighter.KEYWORDS.has(word) ? SimpleCodeHighlighter.KEYWORD : SimpleCodeHighlighter.DEFAULT);
        i = j;
        continue;
      }
      push(ch, SimpleCodeHighlighter.DEFAULT);
      i += 1;
    }
    return spans;
  }

  private static isDigit(c: string): boolean {
    return c >= '0' && c <= '9';
  }

  private static isWordStart(c: string): boolean {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_' || c === '$';
  }

  private static isWordChar(c: string): boolean {
    return SimpleCodeHighlighter.isWordStart(c) || SimpleCodeHighlighter.isDigit(c);
  }
}
