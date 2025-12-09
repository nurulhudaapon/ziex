;; tags.scm - Symbol extraction for ZX
;; Used by ctags, LSP, and code navigation tools

; inherits: zig

;; ============================================================================
;; ZX Components (PascalCase tags)
;; ============================================================================

;; Component definitions (PascalCase tags)
(zx_element
  name: (zx_tag_name) @name
  (#match? @name "^[A-Z]")) @definition.component

(zx_self_closing_element
  name: (zx_tag_name) @name
  (#match? @name "^[A-Z]")) @definition.component

;; ============================================================================
;; @jsImport declarations
;; ============================================================================

(zx_js_import
  name: (identifier) @name) @definition.import
