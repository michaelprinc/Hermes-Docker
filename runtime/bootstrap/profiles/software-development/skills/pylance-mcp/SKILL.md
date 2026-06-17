---
name: "pylance-mcp"
description: "Use the Pylance/Pyright MCP server for Python code intelligence, diagnostics, symbol navigation, and safe refactoring."
version: "1.0.0"
author: "Michael Princ"
tags: [python, pylance, pyright, mcp, code-intelligence, software-development]
metadata:
  hermes:
    tags: [python, static-analysis, mcp]
    required_mcp_servers: [pylance]
---

# Pylance MCP

Use this skill when working on Python files or Python packages and you need language-server-grade context instead of only textual search.

## When to Use

- Inspect type errors, import errors, or unresolved symbols.
- Find definitions, references, signatures, and workspace symbols.
- Check completions or hover/type information before editing unfamiliar Python code.
- Validate Python edits after changing function signatures, imports, or public APIs.

## Workflow

1. Use repository search first to locate the relevant files.
2. Call the `pylance` MCP tools for diagnostics or symbol queries on the target file.
3. Prefer diagnostics and symbol information over guesses about dynamic imports or type inference.
4. After editing Python code, run the local project tests or at least the narrowest relevant validation command.

## Guardrails

- Treat MCP results as analysis input, not as permission to rewrite unrelated code.
- Keep refactors scoped to the requested behavior unless the diagnostics prove a wider change is required.
- If the Pylance MCP server is unavailable, fall back to `pyright`, `ruff`, `pytest`, and repository search.
