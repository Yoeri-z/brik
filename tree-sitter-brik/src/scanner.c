#include "tree_sitter/parser.h"
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>

// Maximum nesting depth of indentation levels
#define MAX_INDENT_DEPTH 256

enum TokenType {
  INDENT,
  DEDENT,
  NEWLINE,
};

typedef struct {
  // Stack of indentation column widths (in spaces)
  uint16_t indent_stack[MAX_INDENT_DEPTH];
  uint16_t stack_size;
} Scanner;

// ─── Lifecycle ────────────────────────────────────────────────────────────────

void *tree_sitter_brik_external_scanner_create(void) {
  Scanner *s = calloc(1, sizeof(Scanner));
  s->indent_stack[0] = 0;
  s->stack_size = 1;
  return s;
}

void tree_sitter_brik_external_scanner_destroy(void *payload) {
  free(payload);
}

unsigned tree_sitter_brik_external_scanner_serialize(void *payload, char *buffer) {
  Scanner *s = (Scanner *)payload;
  unsigned bytes = s->stack_size * sizeof(uint16_t);
  if (bytes > TREE_SITTER_SERIALIZATION_BUFFER_SIZE) {
    bytes = TREE_SITTER_SERIALIZATION_BUFFER_SIZE;
  }
  memcpy(buffer, s->indent_stack, bytes);
  return bytes;
}

void tree_sitter_brik_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  Scanner *s = (Scanner *)payload;
  if (length == 0) {
    s->stack_size = 1;
    s->indent_stack[0] = 0;
  } else {
    s->stack_size = (uint16_t)(length / sizeof(uint16_t));
    memcpy(s->indent_stack, buffer, length);
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

static inline uint16_t current_indent(const Scanner *s) {
  return s->indent_stack[s->stack_size - 1];
}

// Skip horizontal whitespace (spaces + tabs) and return column count.
// Returns the column width consumed, positioning the lexer just past
// the leading whitespace.
static uint16_t skip_whitespace(TSLexer *lexer) {
  uint16_t col = 0;
  while (lexer->lookahead == ' ') {
    lexer->advance(lexer, true);
    col++;
  }
  while (lexer->lookahead == '\t') {
    lexer->advance(lexer, true);
    // Tabs expand to the next 8-space boundary (common convention)
    col = (uint16_t)((col + 8) & ~7u);
  }
  return col;
}

// ─── Main scan function ───────────────────────────────────────────────────────

bool tree_sitter_brik_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid_symbols) {
  Scanner *s = (Scanner *)payload;

  // Only act at the beginning of a line (after a newline).
  // We skip blank lines and comment-only lines entirely.

  // Skip any trailing spaces before looking for a newline
  while (lexer->lookahead == ' ' || lexer->lookahead == '\t') {
    lexer->advance(lexer, true);
  }

  // We must be at a newline to potentially emit INDENT / DEDENT / NEWLINE
  if (lexer->lookahead != '\n' && lexer->lookahead != '\r' && lexer->lookahead != 0) {
    return false;
  }

  // Consume the newline
  if (lexer->lookahead == '\r') {
    lexer->advance(lexer, true);
  }
  if (lexer->lookahead == '\n') {
    lexer->advance(lexer, true);
  }

  // At end-of-file, emit remaining DEDENTs
  if (lexer->lookahead == 0) {
    if (valid_symbols[DEDENT] && s->stack_size > 1) {
      s->stack_size--;
      lexer->result_symbol = DEDENT;
      return true;
    }
    if (valid_symbols[NEWLINE]) {
      lexer->result_symbol = NEWLINE;
      return true;
    }
    return false;
  }

  // Skip blank lines (lines with only whitespace / comments)
  // We peek ahead: consume indent whitespace, then check for newline or '#'
  uint16_t indent = skip_whitespace(lexer);

  // Blank line — don't emit anything structural, keep scanning
  if (lexer->lookahead == '\n' || lexer->lookahead == '\r') {
    // Recursively handle the next newline via the mark trick:
    // Just return false so the parser tries again on the next character.
    return false;
  }

  // Comment line (if brik uses '#' comments — adjust if needed)
  // Skip for now; the parser handles # via normal token rules.

  uint16_t prev_indent = current_indent(s);

  if (indent > prev_indent) {
    // Emit INDENT
    if (valid_symbols[INDENT]) {
      if (s->stack_size < MAX_INDENT_DEPTH) {
        s->indent_stack[s->stack_size++] = indent;
      }
      lexer->result_symbol = INDENT;
      return true;
    }
    return false;
  }

  if (indent < prev_indent) {
    // Emit DEDENT (one level at a time; the parser will call us again)
    if (valid_symbols[DEDENT]) {
      s->stack_size--;
      lexer->result_symbol = DEDENT;
      return true;
    }
    return false;
  }

  // Same indentation level — emit NEWLINE if the parser is expecting one
  if (valid_symbols[NEWLINE]) {
    lexer->result_symbol = NEWLINE;
    return true;
  }

  return false;
}
