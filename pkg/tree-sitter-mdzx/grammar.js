const zx = require('../tree-sitter-zx/grammar');

/**
 * MDZX block grammar: Markdown blocks + ZX components.
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

const PUNCTUATION_CHARACTERS_REGEX = '!-/:-@\\[-`\\{-~';

module.exports = grammar(zx, {
  name: "mdzx",

  rules: {
    // ==========================================
    // MDZX Document Structure
    // ==========================================
    source_file: $ => seq(
      optional($.frontmatter),
      repeat(choice($._blank_line, $._block)),
    ),

    // ==========================================
    // Frontmatter: --- raw Zig --- (MDZX-specific)
    // Raw body so authors can declare Page, var ctx, imports, etc.
    // ==========================================
    frontmatter: $ => seq(
      $.frontmatter_delimiter,
      optional(field('content', $.frontmatter_body)),
      $.frontmatter_delimiter,
    ),

    frontmatter_delimiter: _$ => token(prec(10, /---\n?/)),

    // Everything up to (but not including) the closing --- delimiter line.
    // Tree-sitter regex has no lookaround; match lines that are not exactly `---`.
    frontmatter_body: _$ => token(prec(1, /(?:(?:[^-\n][^\n]*|-|-[^-\n][^\n]*|--|--+[^-\n][^\n]*)?\n)+/)),

    // ==========================================
    // Block Structure (matches tree-sitter-markdown)
    // ==========================================
    _block: $ => choice(
      $.mdzx_component,
      $.zx_expression_block,
      $.atx_heading,
      $.thematic_break,
      $.indented_code_block,
      $.fenced_code_block,
      $.block_quote,
      $.list,
      $.link_reference_definition,
      $.paragraph,
    ),

    // MDZX-specific: ZX components in markdown
    mdzx_component: $ => prec(3, seq(
      choice(
        $.zx_element,
        $.zx_self_closing_element,
      ),
      $._newline,
    )),

    // Override ZX element rules so '>' / '/>' beat blockquote '>'
    zx_self_closing_element: $ => seq(
      '<',
      field('name', $.zx_tag_name),
      repeat($.zx_attribute),
      token(prec(5, '/>')),
    ),
    zx_start_tag: $ => seq(
      '<',
      field('name', $.zx_tag_name),
      repeat($.zx_attribute),
      token(prec(5, '>')),
    ),
    zx_end_tag: $ => seq(
      '</',
      field('name', $.zx_tag_name),
      token(prec(5, '>')),
    ),

    // ==========================================
    // ATX Headings
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
    _atx_heading1: $ => prec(1, seq($.atx_h1_marker, optional($._atx_heading_content), $._newline)),
    _atx_heading2: $ => prec(1, seq($.atx_h2_marker, optional($._atx_heading_content), $._newline)),
    _atx_heading3: $ => prec(1, seq($.atx_h3_marker, optional($._atx_heading_content), $._newline)),
    _atx_heading4: $ => prec(1, seq($.atx_h4_marker, optional($._atx_heading_content), $._newline)),
    _atx_heading5: $ => prec(1, seq($.atx_h5_marker, optional($._atx_heading_content), $._newline)),
    _atx_heading6: $ => prec(1, seq($.atx_h6_marker, optional($._atx_heading_content), $._newline)),

    _atx_heading_content: $ => prec(1, seq(
      optional($._whitespace),
      field('heading_content', alias($._line, $.inline)),
    )),

    atx_h1_marker: _$ => token(prec(2, /# /)),
    atx_h2_marker: _$ => token(prec(2, /## /)),
    atx_h3_marker: _$ => token(prec(2, /### /)),
    atx_h4_marker: _$ => token(prec(2, /#### /)),
    atx_h5_marker: _$ => token(prec(2, /##### /)),
    atx_h6_marker: _$ => token(prec(2, /###### /)),

    // ==========================================
    // Thematic Break
    // ==========================================
    thematic_break: $ => $._thematic_break,
    _thematic_break: _$ => token(prec(1, /(\*[ \t]*\*[ \t]*\*[\* \t]*|_[ \t]*_[ \t]*_[_ \t]*|-[ \t]*-[ \t]*-[- \t]*)\n/)),

    // ==========================================
    // Indented Code Block
    // ==========================================
    indented_code_block: $ => prec.right(repeat1($._indented_chunk)),
    _indented_chunk: _$ => token(prec(1, /    [^\n]*\n/)),

    // ==========================================
    // Fenced Code Block
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
    // Whole-line tokens beat ZX `{...}`; end-fence tokens are prec(10) so they win over content.
    code_fence_content: $ => prec.right(repeat1(alias($._code_fence_line, $.raw_line))),
    _code_fence_line: _$ => token(prec(6, /[^\n]*\n/)),
    info_string: $ => $.language,
    language: _$ => token(/[A-Za-z0-9_+\#-]+/),

    _fenced_code_block_start_backtick: _$ => token(prec(3, /`{3,}/)),
    _fenced_code_block_end_backtick: _$ => token(prec(10, /`{3,}[ \t]*\n?/)),
    _fenced_code_block_start_tilde: _$ => token(prec(3, /~{3,}/)),
    _fenced_code_block_end_tilde: _$ => token(prec(10, /~{3,}[ \t]*\n?/)),

    // ==========================================
    // Block Quote
    // ==========================================
    block_quote: $ => prec.right(repeat1($._block_quote_line)),
    _block_quote_line: $ => seq(
      alias($._block_quote_start, $.block_quote_marker),
      // `+` not `*`: blank `>` lines omit content so the next `>` starts a new line
      optional(field('content', alias(/[^\n]+/, $.inline))),
      $._newline,
    ),
    _block_quote_start: _$ => token(prec(2, />[ \t]?/)),

    // ==========================================
    // Lists
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
      optional(field('content', alias(/[^\n]*/, $.inline))),
      $._newline,
    ),

    list_marker_plus: _$ => token(prec(2, /[ \t]*\+[ \t]+/)),
    list_marker_minus: _$ => token(prec(2, /[ \t]*-[ \t]+/)),
    list_marker_star: _$ => token(prec(2, /[ \t]*\*[ \t]+/)),
    list_marker_dot: _$ => token(prec(2, /[ \t]*[0-9]+\.[ \t]+/)),
    list_marker_parenthesis: _$ => token(prec(2, /[ \t]*[0-9]+\)[ \t]+/)),

    // Must outrank the list-item content `/[^\n]*/` token.
    task_list_marker_checked: _$ => token(prec(3, /\[[xX]\][ \t]+/)),
    task_list_marker_unchecked: _$ => token(prec(3, /\[[ \t]\][ \t]+/)),

    // ==========================================
    // Link Reference Definition
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

    link_destination: $ => choice(
      seq('<', alias(/[^<>\n]+/, $.uri), '>'),
      alias(/[^\s\(\)\[\]"']+/, $.uri),
    ),

    link_title: $ => choice(
      seq('"', repeat(choice($._word, $._whitespace, $.backslash_escape)), '"'),
      seq("'", repeat(choice($._word, $._whitespace, $.backslash_escape)), "'"),
    ),

    // ==========================================
    // Paragraph
    // Soft-wrapped continuations only (soft_break + line pairs), so a blank
    // line ends the paragraph.
    // ==========================================
    paragraph: $ => prec(-1, seq(
      alias(seq($._line, repeat(seq($._soft_line_break, $._line))), $.inline),
      $._newline,
    )),

    // ==========================================
    // Helpers (block-level only; no inline markup)
    // ==========================================
    backslash_escape: $ => $._backslash_escape,
    _backslash_escape: _$ => new RegExp('\\\\[' + PUNCTUATION_CHARACTERS_REGEX + ']'),

    _newline: _$ => /\n|\r\n?/,
    _soft_line_break: _$ => /\n/,
    _line: $ => prec.right(repeat1(choice($._word, $._whitespace, $._punctuation))),
    _word: _$ => new RegExp('[^' + PUNCTUATION_CHARACTERS_REGEX + ' \\t\\n\\r]+'),
    _whitespace: _$ => /[ \t]+/,
    _punctuation: _$ => new RegExp('[' + PUNCTUATION_CHARACTERS_REGEX + ']'),
    _text_inline_no_link: _$ => /[^\n\[\]\\]+/,
    _blank_line: _$ => token(prec(1, /[ \t]*\n/)),

    // Keep // in URLs from being treated as Zig comments
    comment: _$ => token(prec(-10, seq('//', /.*/))),
  },
});
