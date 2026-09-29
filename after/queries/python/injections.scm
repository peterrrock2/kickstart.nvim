; extends

; Parse inline markup directly so docstring indentation does not become a Markdown code block.
([
  (module
    . (comment)*
    . (expression_statement
        (string
          (string_start) @_start
          (string_content) @injection.content)))
  (function_definition
    body: (block
      . (comment)*
      . (expression_statement
          (string
            (string_start) @_start
            (string_content) @injection.content))))
  (class_definition
    body: (block
      . (comment)*
      . (expression_statement
          (string
            (string_start) @_start
            (string_content) @injection.content))))
  ]
  (#match? @_start "^[rRuU]?(\"\"\"|''')$")
  (#set! injection.language "markdown_inline")
  (#set! injection.include-children))
