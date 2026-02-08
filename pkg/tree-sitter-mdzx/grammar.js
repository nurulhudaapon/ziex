const zx = require('../tree-sitter-zx/grammar');

/**
 * @file MDZX is a MDX-like format for Zig - combining Markdown with ZX components.
 * @author Nurul Huda (Apon) <me@nurulhudaapon.com>
 * @license MIT
 * 
 * MDZX file structure:
 * 1. Frontmatter with Zig declarations (--- pub const / const statements ---)
 * 2. Markdown content with embedded ZX components
 * 
 * Grammar structure aligned with tree-sitter-markdown for maximum compatibility.
 * Node names match tree-sitter-markdown exactly where possible.
 * Inherits all zx_* rules from tree-sitter-zx grammar.
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

const PUNCTUATION_CHARACTERS_REGEX = '!-/:-@\\[-`\\{-~';
const PUNCTUATION_CHARACTERS_ARRAY = [
    '!', '"', '#', '$', '%', '&', "'", '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<',
    '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~'
];

module.exports = grammar(zx, {
  name: "mdzx",

  rules: {
    // ==========================================
    // MDZX Document Structure (like markdown's document)
    // ==========================================
    source_file: $ => seq(
      optional($.frontmatter),
      repeat($._block),
    ),

    // ==========================================
    // Frontmatter: --- zig declarations --- (MDZX-specific)
    // ==========================================
    frontmatter: $ => seq(
      $.frontmatter_delimiter,
      repeat($.zig_declaration),
      $.frontmatter_delimiter,
    ),

    frontmatter_delimiter: _$ => token(prec(10, /---\n?/)),

    zig_declaration: $ => choice(
      $.pub_const_declaration,
      $.const_declaration,
    ),

    pub_const_declaration: $ => seq(
      'pub',
      'const',
      field('name', $.identifier),
      optional(seq(':', field('type', $.type_expression))),
      '=',
      field('value', $.expression),
      ';',
    ),

    const_declaration: $ => seq(
      'const',
      field('name', $.identifier),
      optional(seq(':', field('type', $.type_expression))),
      '=',
      field('value', $.expression),
      ';',
    ),

    // ==========================================
    // Block Structure (matches tree-sitter-markdown)
    // ==========================================
    _block: $ => choice(
      $.mdzx_component,           // MDZX-specific
      $.zx_expression_block,      // MDZX-specific
      $.atx_heading,
      $.thematic_break,
      $.indented_code_block,
      $.fenced_code_block,
      $.block_quote,
      $.list,
      $.link_reference_definition,
      $.paragraph,
      $._blank_line,
    ),

    // MDZX-specific: ZX components in markdown
    mdzx_component: $ => choice(
      $.zx_element,
      $.zx_self_closing_element,
    ),

    // ==========================================
    // ATX Headings (exactly like tree-sitter-markdown)
    // https://github.github.com/gfm/#atx-headings
    // ==========================================
    atx_heading: $ => choice(
      $._atx_heading1,
      $._atx_heading2,
      $._atx_heading3,
      $._atx_heading4,
      $._atx_heading5,
      $._atx_heading6,
    ),
    _atx_heading1: $ => prec(1, seq($.atx_h1_marker, optional(field('heading_content', $.inline)), $._newline)),
    _atx_heading2: $ => prec(1, seq($.atx_h2_marker, optional(field('heading_content', $.inline)), $._newline)),
    _atx_heading3: $ => prec(1, seq($.atx_h3_marker, optional(field('heading_content', $.inline)), $._newline)),
    _atx_heading4: $ => prec(1, seq($.atx_h4_marker, optional(field('heading_content', $.inline)), $._newline)),
    _atx_heading5: $ => prec(1, seq($.atx_h5_marker, optional(field('heading_content', $.inline)), $._newline)),
    _atx_heading6: $ => prec(1, seq($.atx_h6_marker, optional(field('heading_content', $.inline)), $._newline)),

    atx_h1_marker: _$ => token(prec(2, /# /)),
    atx_h2_marker: _$ => token(prec(2, /## /)),
    atx_h3_marker: _$ => token(prec(2, /### /)),
    atx_h4_marker: _$ => token(prec(2, /#### /)),
    atx_h5_marker: _$ => token(prec(2, /##### /)),
    atx_h6_marker: _$ => token(prec(2, /###### /)),

    // ==========================================
    // Thematic Break (exactly like tree-sitter-markdown)
    // https://github.github.com/gfm/#thematic-breaks
    // A thematic break is a line containing only the marker characters (and spaces)
    // It must not have any other content on the same line
    // ==========================================
    thematic_break: $ => $._thematic_break,
    _thematic_break: _$ => token(prec(1, /(\*[ \t]*\*[ \t]*\*[\* \t]*|_[ \t]*_[ \t]*_[_ \t]*|-[ \t]*-[ \t]*-[- \t]*)\n/)),

    // ==========================================
    // Indented Code Block (exactly like tree-sitter-markdown)
    // https://github.github.com/gfm/#indented-code-blocks
    // ==========================================
    indented_code_block: $ => prec.right(repeat1($._indented_chunk)),
    _indented_chunk: _$ => token(prec(1, /    [^\n]*\n/)),

    // ==========================================
    // Fenced Code Block (exactly like tree-sitter-markdown)
    // https://github.github.com/gfm/#fenced-code-blocks
    // ==========================================
    fenced_code_block: $ => prec.right(choice(
      seq(
        alias($._fenced_code_block_start_backtick, $.fenced_code_block_delimiter),
        optional($._whitespace),
        optional($.info_string),
        $._newline,
        optional($.code_fence_content),
        optional(seq(alias($._fenced_code_block_end_backtick, $.fenced_code_block_delimiter), optional($._newline))),
      ),
      seq(
        alias($._fenced_code_block_start_tilde, $.fenced_code_block_delimiter),
        optional($._whitespace),
        optional($.info_string),
        $._newline,
        optional($.code_fence_content),
        optional(seq(alias($._fenced_code_block_end_tilde, $.fenced_code_block_delimiter), optional($._newline))),
      ),
    )),
    // Code fence content: raw text lines, with optional mdzx_component embedded
    // Each line is captured as raw text until we hit the closing fence
    code_fence_content: $ => prec.right(repeat1(choice(
      $.mdzx_component,
      alias($._code_fence_line, $.raw_line),
    ))),
    // Raw code line - captures entire line including any special chars
    // Must not match closing fence (3+ backticks or tildes at start of line)
    _code_fence_line: _$ => token(prec(5, /[^\n`~][^\n]*\n|[`~]{1,2}[^\n]*\n|\n/)),
    info_string: $ => choice(
      seq($.language, optional($._line)),
      seq(repeat1(choice('{', '}')), optional(choice(
        seq($.language, optional($._line)),
        seq($._whitespace, optional($._line)),
      )))
    ),
    language: $ => prec.right(repeat1(choice($._word, $.backslash_escape))),

    _fenced_code_block_start_backtick: _$ => token(prec(3, /`{3,}/)),
    _fenced_code_block_end_backtick: _$ => token(prec(3, /`{3,}/)),
    _fenced_code_block_start_tilde: _$ => token(prec(3, /~{3,}/)),
    _fenced_code_block_end_tilde: _$ => token(prec(3, /~{3,}/)),

    // ==========================================
    // Block Quote (exactly like tree-sitter-markdown)
    // https://github.github.com/gfm/#block-quotes
    // ==========================================
    block_quote: $ => seq(
      alias($._block_quote_start, $.block_quote_marker),
      optional($._line),
      $._newline,
    ),
    _block_quote_start: _$ => token(prec(2, />[ \t]?/)),

    // ==========================================
    // Lists (exactly like tree-sitter-markdown)
    // https://github.github.com/gfm/#lists
    // ==========================================
    list: $ => prec.right(choice(
      $._list_plus,
      $._list_minus,
      $._list_star,
      $._list_dot,
      $._list_parenthesis
    )),
    _list_plus: $ => prec.right(repeat1(alias($._list_item_plus, $.list_item))),
    _list_minus: $ => prec.right(repeat1(alias($._list_item_minus, $.list_item))),
    _list_star: $ => prec.right(repeat1(alias($._list_item_star, $.list_item))),
    _list_dot: $ => prec.right(repeat1(alias($._list_item_dot, $.list_item))),
    _list_parenthesis: $ => prec.right(repeat1(alias($._list_item_parenthesis, $.list_item))),

    _list_item_plus: $ => seq($.list_marker_plus, $._list_item_content),
    _list_item_minus: $ => seq($.list_marker_minus, $._list_item_content),
    _list_item_star: $ => seq($.list_marker_star, $._list_item_content),
    _list_item_dot: $ => seq($.list_marker_dot, $._list_item_content),
    _list_item_parenthesis: $ => seq($.list_marker_parenthesis, $._list_item_content),

    _list_item_content: $ => seq(
      optional(choice($.task_list_marker_checked, $.task_list_marker_unchecked)),
      optional($._line),
      $._newline,
    ),

    list_marker_plus: _$ => token(prec(2, /[ \t]*\+[ \t]+/)),
    list_marker_minus: _$ => token(prec(2, /[ \t]*-[ \t]+/)),
    list_marker_star: _$ => token(prec(2, /[ \t]*\*[ \t]+/)),
    list_marker_dot: _$ => token(prec(2, /[ \t]*[0-9]+\.[ \t]+/)),
    list_marker_parenthesis: _$ => token(prec(2, /[ \t]*[0-9]+\)[ \t]+/)),

    // Task list markers (GFM extension)
    task_list_marker_checked: _$ => prec(1, /\[[xX]\][ \t]/),
    task_list_marker_unchecked: _$ => prec(1, /\[[ \t]\][ \t]/),

    // ==========================================
    // Link Reference Definition (like tree-sitter-markdown)
    // https://github.github.com/gfm/#link-reference-definitions
    // ==========================================
    link_reference_definition: $ => prec(5, seq(
      optional($._whitespace),
      $.link_label,
      ':',
      optional($._whitespace),
      $.link_destination,
      optional(seq($._whitespace, $.link_title)),
      $._newline,
    )),

    link_label: $ => seq('[', repeat1(choice($._text_inline_no_link, $.backslash_escape)), ']'),

    // Link destination handles full URLs including protocol (https://), dots, etc.
    link_destination: $ => choice(
      // Angle bracket URLs: <url>
      seq('<', alias(/[^<>\n]+/, $.uri), '>'),
      // Bare URLs: must handle https://example.com/path properly
      alias(/[^\s\(\)\[\]"']+/, $.uri),
    ),

    link_title: $ => choice(
      seq('"', repeat(choice($._word, $._whitespace, $.backslash_escape)), '"'),
      seq("'", repeat(choice($._word, $._whitespace, $.backslash_escape)), "'"),
    ),

    // ==========================================
    // Paragraph (exactly like tree-sitter-markdown)
    // https://github.github.com/gfm/#paragraphs
    // ==========================================
    paragraph: $ => prec(-1, seq(
      $.inline,
      $._newline
    )),

    // ==========================================
    // Inline Elements (aligned with tree-sitter-markdown-inline)
    // ==========================================
    inline: $ => prec.right(repeat1($._inline_element)),
    
    _inline_element: $ => choice(
      $.code_span,
      $.bold_italic,      // Must come before strong_emphasis
      $.strong_emphasis,  // Must come before emphasis
      $.emphasis,
      $.strikethrough,
      $.inline_link,
      $.full_reference_link,
      $.image,
      $.autolink,
      $.backslash_escape,
      $._inline_text,
      $._whitespace,
      $._soft_line_break,
    ),

    // Inline text: match any characters except inline delimiters and newlines
    // This is more permissive to capture URLs and other content
    _inline_text: _$ => token(prec(-1, /[^\n`\*_~\[\]!<\\]+/)),
    _text_inline_no_link: _$ => /[^\n\[\]\\]+/,

    // Code span (like tree-sitter-markdown-inline)
    code_span: $ => prec(2, seq(
      alias(/`+/, $.code_span_delimiter),
      optional(alias(/[^`\n]+/, $.code_span_content)),
      alias(/`+/, $.code_span_delimiter),
    )),

    // Emphasis (like tree-sitter-markdown-inline) - *text* or _text_
    emphasis: $ => prec.dynamic(1, choice(
      seq('*', alias(/[^*\n]+/, $.emphasis_content), '*'),
      seq('_', alias(/[^_\n]+/, $.emphasis_content), '_'),
    )),

    // Strong emphasis (like tree-sitter-markdown-inline) - **text** or __text__
    strong_emphasis: $ => prec.dynamic(2, choice(
      seq('**', alias(/[^*\n]+/, $.strong_emphasis_content), '**'),
      seq('__', alias(/[^_\n]+/, $.strong_emphasis_content), '__'),
    )),

    // Bold + Italic (***text*** or ___text___)
    bold_italic: $ => prec.dynamic(5, choice(
      seq('***', alias(/[^*\n]+/, $.bold_italic_content), '***'),
      seq('___', alias(/[^_\n]+/, $.bold_italic_content), '___'),
    )),

    // Strikethrough (GFM extension) - ~~text~~
    strikethrough: $ => prec.dynamic(2, seq(
      '~~',
      alias(/[^~\n]+/, $.strikethrough_content),
      '~~',
    )),

    // Inline link (like tree-sitter-markdown-inline)
    inline_link: $ => prec(3, seq(
      $.link_text,
      '(',
      optional($._whitespace),
      optional(alias(/[^\s\)"']+/, $.link_destination)),
      optional(seq($._whitespace, $.link_title)),
      optional($._whitespace),
      ')',
    )),
    link_text: $ => seq('[', repeat(choice($._text_inline_no_link, $.backslash_escape)), ']'),

    // Full reference link: [text][label]
    full_reference_link: $ => prec(2, seq(
      $.link_text,
      '[',
      optional(alias(/[^\]]+/, $.link_label)),
      ']',
    )),

    // Image (like tree-sitter-markdown-inline)
    image: $ => prec(3, seq(
      '!',
      $.link_text,
      '(',
      optional($._whitespace),
      optional(alias(/[^\s\)"']+/, $.link_destination)),
      optional(seq($._whitespace, $.link_title)),
      optional($._whitespace),
      ')',
    )),

    // Autolink (like tree-sitter-markdown-inline)
    autolink: $ => prec(2, seq(
      '<',
      alias(/[a-zA-Z][a-zA-Z0-9+.-]*:[^\s<>]*/, $.uri),
      '>'
    )),

    // Backslash escape (exactly like tree-sitter-markdown)
    backslash_escape: $ => $._backslash_escape,
    _backslash_escape: _$ => new RegExp('\\\\[' + PUNCTUATION_CHARACTERS_REGEX + ']'),

    // ==========================================
    // Helper Rules (exactly like tree-sitter-markdown)
    // ==========================================
    _newline: _$ => /\n|\r\n?/,
    _soft_line_break: _$ => /\n/,
    _line: $ => prec.right(repeat1(choice($._word, $._whitespace, $._punctuation))),
    _word: _$ => new RegExp('[^' + PUNCTUATION_CHARACTERS_REGEX + ' \\t\\n\\r]+'),
    _whitespace: _$ => /[ \t]+/,
    _punctuation: _$ => new RegExp('[' + PUNCTUATION_CHARACTERS_REGEX + ']'),
    _blank_line: _$ => token(prec(-1, /[ \t]*\n/)),
    
    // Override Zig comment to have very low precedence in markdown context
    // so that // in URLs is not mistaken for comments
    comment: _$ => token(prec(-10, seq('//', /.*/))),

    // All zx_* rules inherited from tree-sitter-zx grammar
  },
});
