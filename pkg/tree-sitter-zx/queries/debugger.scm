(variable_declaration
  (identifier) @debug-variable
  (#not-eq? @debug-variable "_"))
(assignment_expression right: (identifier) @debug-variable)

(initializer_list (identifier) @debug-variable)

(for_statement (identifier) @debug-variable)
(if_statement condition: (identifier) @debug-variable)
(while_statement condition: (identifier) @debug-variable)

(for_expression (identifier) @debug-variable)
(switch_expression (identifier) @debug-variable)
(if_expression condition: (identifier) @debug-variable)
(while_expression condition: (identifier) @debug-variable)

(binary_expression (identifier) @debug-variable)
(catch_expression (identifier) @debug-variable)
(unary_expression argument: (identifier) @debug-variable)

(call_expression (identifier) @debug-variable)
(builtin_function
  (arguments (identifier) @debug-variable))
(parameter name: (identifier) @debug-variable)

(parenthesized_expression (identifier) @debug-variable)

(payload (identifier) @debug-variable)

(index_expression index: (identifier) @debug-variable)
(range_expression (identifier) @debug-variable)

(break_expression (identifier) @debug-variable)
(continue_expression (identifier) @debug-variable)
(return_expression (identifier) @debug-variable)
(try_expression (identifier) @debug-variable)

(switch_case "=>" (identifier) @debug-variable)

(block) @debug-scope
(function_declaration) @debug-scope
