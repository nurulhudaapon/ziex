; MDZX Debugger

; Variables in frontmatter declarations
(pub_const_declaration
  name: (identifier) @debug-variable)

(const_declaration
  name: (identifier) @debug-variable)

; Expressions
(assignment_expression right: (identifier) @debug-variable)
(initializer_list (identifier) @debug-variable)
(field_expression object: (identifier) @debug-variable)
(call_expression function: (identifier) @debug-variable)
(builtin_function
  (arguments (identifier) @debug-variable))

; Scopes
(frontmatter) @debug-scope
(zx_element) @debug-scope
