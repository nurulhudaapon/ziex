; MDZX Text Objects
; Aligned with tree-sitter-markdown naming conventions

; Frontmatter as a block
(frontmatter) @block.around

; ZX elements
(zx_element
  (zx_start_tag)
  (_)* @block.inside
  (zx_end_tag)) @block.around

; Zig declarations in frontmatter
(pub_const_declaration) @function.around
(const_declaration) @function.around

; Markdown block elements
(atx_heading) @block.around
(fenced_code_block) @block.around
(block_quote) @block.around
(list) @block.around
(list_item) @block.around
(paragraph) @block.around

; Inline text objects
(strong_emphasis) @text.strong
(emphasis) @text.emphasis
(code_span) @text.code
(inline_link) @text.link
(image) @text.link

; Comments
(comment)+ @comment.around
