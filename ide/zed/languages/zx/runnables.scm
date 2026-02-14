; Tag unit tests
(
    (test_declaration
        (string (string_content) @name @ZIG_TEST_NAME)
    ) @run
    (#set! tag zig-test)
)

; Tag main
(
    (function_declaration
        name: (identifier) @_name
    ) @run
    (#match? @_name "main")
    (#set! tag zig-build-run)
)
