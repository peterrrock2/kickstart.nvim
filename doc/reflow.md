# Reflow edge cases

`:Reflow` targets 98 display columns, including indentation and comment markers. Syntax takes
priority over fitting every line: an indivisible unit can exceed the width, and a paragraph is
left unchanged when wrapping it would change its Markdown block structure. Use `:Reflow 80`
to choose another width, or **Space, Shift+R** for the default width.

## Handling rules

| Case | Handling |
| --- | --- |
| Years and numbers within prose | Wrap as prose without introducing numbered-list indentation. |
| Ordered lists, nested lists, checkboxes, blockquotes | Preserve their structure and continuation indentation. |
| A wrap puts `#`, `>`, `1.`, or another block marker at the start of a line | Reject the paragraph edit if the Markdown block structure changes. |
| Inline and reference links, images, autolinks | Keep each unit intact; join soft line breaks inside recognized link labels. |
| Inline code and single-line dollar math | Keep each unit intact, even if it exceeds the width. |
| Multiline code spans or math | Preserve the containing paragraph, including delimiter placement. |
| Inline HTML tags with spaced attributes | Keep tags intact while wrapping surrounding prose. |
| Brackets the inline parser cannot resolve, including some nested links | Preserve the containing paragraph. |
| Tables, with or without outer pipes | Preserve the table layout and contents. |
| Headings, including underlined headings | Preserve heading text and layout. |
| Fenced/indented code, HTML blocks, front matter, reference definitions | Leave these blocks unchanged. |
| Explicit Markdown hard breaks | Preserve lines ending in two spaces or a backslash. |
| Python docstring opening quotes | Keep the existing placement; an attached summary stays attached. |
| Google-style fields | Wrap descriptions with hanging indentation, including descriptions that initially start on the next line. |
| Google-style `Note:` and `Notes:` sections | Wrap prose paragraphs at their existing indentation without field-style hanging indentation. |
| NumPy-style fields | Preserve declarations and wrap indented descriptions. |
| Doctest prompts and output | Preserve from `>>>` through the next blank line. |
| Unsupported docstring structures, such as Sphinx fields | Leave them unchanged rather than guess their indentation rules. |
| Python ordinary strings, concatenated literals, inline comments | Leave them unchanged. Only standalone comments and actual triple-quoted docstrings are eligible. |
| Rust line and block comments | Preserve comment kind and prefixes; wrap uniformly indented prose. |
| Nested Rust block comments | Leave them unchanged. |
| Unicode, nonbreaking spaces, literal placeholder characters | Preserve characters and use display width; protected-unit placeholders avoid characters already in the text. |

The block-structure check is a conservative safeguard, not a complete Markdown renderer comparison.
The installed Tree-sitter grammars determine which syntax is recognized. Custom Markdown extensions
and unfamiliar documentation markup may need an explicit ignore region.

## Explicit preservation

In Markdown, surround a region with `<!-- reflow: off -->` and `<!-- reflow: on -->`.
In Python use `# reflow: off` / `# reflow: on`; in Rust use `// reflow: off` /
`// reflow: on`. The corresponding `fmt: off` / `fmt: on` directives also work.
An unmatched `off` preserves the rest of the file. A paragraph crossing a disabled region is
preserved as a whole.

Markdown also recognizes `<!-- prettier-ignore -->` before the next block, and
`<!-- prettier-ignore-start -->` / `<!-- prettier-ignore-end -->` around a region.
These follow the next-node and range conventions described in
[Prettier's ignore documentation](https://prettier.io/docs/ignore); this command accepts range
markers without requiring blank lines around them.

## Selection and editor behavior

Normal-mode **Space, Shift+R** reflows the whole buffer. Visual mode limits it to the selected
lines. Only complete eligible paragraphs are reflowed; Python docstrings and Rust block comments
must be selected in full. A partial selection may therefore do nothing.

All source edits form one undo step. Reflow leaves the source buffer's formatting options and
registers alone, and removes its scratch buffer on success or failure. Missing parsers and
Python/Rust syntax errors stop the command before source edits are applied.

## Regression checks

Run from the configuration directory:

```sh
NVIM_LOG_FILE=/tmp/nvim-reflow-test.log nvim -n --clean --headless -i NONE -l tests/reflow.lua
NVIM_LOG_FILE=/tmp/nvim-reflow-test.log nvim -n --clean --headless -i NONE -l tests/reflow_edges.lua
```

The original suite includes the reported retrieval-guide and docstring examples. The edge-case
suite exercises 317 cases, including a width/marker matrix, protected units at widths from 1 to
120, double-width ambiguous characters, ignore/resume behavior, selections, undo/redo, and parser
failure. Each successful formatting case is reflowed again to check stability.

The expected behavior draws on [CommonMark's block and inline rules](https://spec.commonmark.org/spec/)
and the [reStructuredText doctest convention](https://docutils.sourceforge.io/0.22/docs/ref/rst/restructuredtext.html#doctest-blocks).
Multiline code spans are deliberately preserved even where CommonMark permits normalizing their
line breaks; keeping their source layout avoids surprises in documentation examples.
