/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

const PUNCTUATION_CHARACTERS_REGEX = '!-/:-@\\[-`\\{-~';

module.exports = grammar({
  name: "mdzx_inline",

  rules: {
    inline: $ => prec.right(repeat1($._inline_element)),

    _inline_element: $ => choice(
      $.code_span,
      $.bold_italic,
      $.strong_emphasis,
      $.emphasis,
      $.strikethrough,
      $.inline_link,
      $.full_reference_link,
      $.image,
      $.autolink,
      $.backslash_escape,
      // Named (not `_…`) so plain text survives in the syntax tree for emit.
      $.text,
      $.whitespace,
      $.soft_line_break,
    ),

    text: _$ => token(prec(-1, /[^\n`\*_~\[\]!<\\]+/)),
    whitespace: _$ => /[ \t]+/,
    soft_line_break: _$ => /\n/,
    _text_inline_no_link: _$ => /[^\n\[\]\\]+/,

    code_span: $ => prec(2, seq(
      alias(/`+/, $.code_span_delimiter),
      optional(alias(/[^`\n]+/, $.code_span_content)),
      alias(/`+/, $.code_span_delimiter),
    )),

    emphasis: $ => prec.dynamic(1, choice(
      seq('*', alias(/[^*\n]+/, $.emphasis_content), '*'),
      seq('_', alias(/[^_\n]+/, $.emphasis_content), '_'),
    )),

    strong_emphasis: $ => prec.dynamic(2, choice(
      seq('**', alias(/[^*\n]+/, $.strong_emphasis_content), '**'),
      seq('__', alias(/[^_\n]+/, $.strong_emphasis_content), '__'),
    )),

    bold_italic: $ => prec.dynamic(5, choice(
      seq('***', alias(/[^*\n]+/, $.bold_italic_content), '***'),
      seq('___', alias(/[^_\n]+/, $.bold_italic_content), '___'),
    )),

    strikethrough: $ => prec.dynamic(2, seq(
      '~~',
      alias(/[^~\n]+/, $.strikethrough_content),
      '~~',
    )),

    inline_link: $ => prec(3, seq(
      $.link_text,
      '(',
      optional($._whitespace),
      optional($.link_destination),
      optional(seq($._whitespace, $.link_title)),
      optional($._whitespace),
      ')',
    )),
    link_text: $ => seq(
      '[',
      repeat(choice(
        alias($._text_inline_no_link, $.link_text_content),
        $.backslash_escape,
      )),
      ']',
    ),

    full_reference_link: $ => prec(2, seq(
      $.link_text,
      '[',
      optional(alias(/[^\]]+/, $.link_label)),
      ']',
    )),

    image: $ => prec(3, seq(
      '!',
      $.link_text,
      '(',
      optional($._whitespace),
      optional($.link_destination),
      optional(seq($._whitespace, $.link_title)),
      optional($._whitespace),
      ')',
    )),

    link_destination: $ => choice(
      seq('<', alias(/[^<>\n]+/, $.uri), '>'),
      // Keep the node named `link_destination` (don't alias the whole rule away)
      /[^\s\(\)\[\]"']+/,
    ),

    link_title: $ => choice(
      seq('"', repeat(choice($._word, $._whitespace, $.backslash_escape)), '"'),
      seq("'", repeat(choice($._word, $._whitespace, $.backslash_escape)), "'"),
    ),

    autolink: $ => prec(2, seq(
      '<',
      alias(/[a-zA-Z][a-zA-Z0-9+.-]*:[^\s<>]*/, $.uri),
      '>'
    )),

    backslash_escape: $ => $._backslash_escape,
    _backslash_escape: _$ => new RegExp('\\\\[' + PUNCTUATION_CHARACTERS_REGEX + ']'),

    _word: _$ => new RegExp('[^' + PUNCTUATION_CHARACTERS_REGEX + ' \\t\\n\\r]+'),
    _whitespace: _$ => /[ \t]+/,
  },
});
