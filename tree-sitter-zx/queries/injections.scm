;; injections.scm - Language injection for ZX
;; Enables proper highlighting of embedded languages

; inherits: zig

;; ============================================================================
;; Zig Expression Injection
;; ============================================================================

;; Inject Zig syntax into expression blocks
;; This ensures {expressions} get proper Zig highlighting
((zx_expression_block
  (expression) @injection.content)
  (#set! injection.language "zig")
  (#set! injection.include-children))

;; ============================================================================
;; CSS Injection
;; ============================================================================

;; Inject CSS into style attributes
((zx_regular_attribute
  (zx_attribute_name) @_attr
  (zx_attribute_value
    (zx_string_literal) @injection.content))
  (#eq? @_attr "style")
  (#set! injection.language "css"))
