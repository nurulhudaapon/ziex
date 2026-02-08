; MDZX Indentation
; Aligned with tree-sitter-markdown naming conventions

; Frontmatter
(frontmatter) @indent.begin

; ZX elements
(zx_element) @indent.begin
(zx_start_tag ">" @indent.begin)
(zx_end_tag) @indent.end

; Zig blocks
[
  (block)
  (switch_expression)
  (initializer_list)
] @indent.begin

(block "}" @indent.end)

(_ "[" "]" @end) @indent
(_ "{" "}" @end) @indent
(_ "(" ")" @end) @indent

; Block-level markdown elements
(fenced_code_block) @indent.begin
(block_quote) @indent.begin
(list) @indent.begin
(list_item) @indent.begin

[
  (comment)
  (multiline_string)
  (paragraph)
] @indent.ignore
