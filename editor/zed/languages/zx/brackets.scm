("(" @open ")" @close)
("[" @open "]" @close)
("{" @open "}" @close)
("\"" @open "\"" @close)
(payload "|" @open "|" @close)
("'" @open "'" @close)

; ZX-specific brackets
(zx_element
  "<" @open
  ">" @close)

(zx_element
  "</" @open
  ">" @close)

(zx_self_closing_element
  "<" @open
  "/>" @close)

(zx_fragment
  "<>" @open
  "</>" @close)

(zx_expression_block
  "{" @open
  "}" @close)
