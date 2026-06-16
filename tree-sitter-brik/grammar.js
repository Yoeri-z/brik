/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: 'brik',

  // External tokens: the scanner handles indent-sensitive whitespace
  externals: $ => [
    $._indent,
    $._dedent,
    $._newline,
  ],

  // Reserve keywords so identifiers cannot shadow them
  word: $ => $.identifier,

  // Inline rules that only appear in one place to reduce noise
  inline: $ => [
    $.declaration,
    $.literal,
  ],

  // Precedence levels (higher = tighter binding)
  // unary > binary > call > expression
  conflicts: $ => [
    [$.expression, $.param],
    [$.expression, $.param, $.arg],
    [$.expression, $.arg],
    [$.type_expr, $.expression],
    [$.type_expr, $.expression, $.param],
    [$.type_expr, $.param],
    [$.type_expr],
    [$.variable_decl],
    [$.type_decl],
    [$.if_expr, $.lambda],
  ],

  rules: {

    // -----------------------------------------------------------------------
    // Top-level
    // -----------------------------------------------------------------------

    program: $ => seq(
      optional($.library_decl),
      repeat($.import_decl),
      repeat($._statement)
    ),

    library_decl: $ => seq('library', $.identifier),

    // -----------------------------------------------------------------------
    // Import
    // -----------------------------------------------------------------------

    import_decl: $ => seq(
      'import',
      $.module_path,
      optional(seq('as', $.identifier))
    ),

    module_path: $ => seq(
      $.identifier,
      repeat(seq('.', $.identifier))
    ),

    // -----------------------------------------------------------------------
    // Statements
    // -----------------------------------------------------------------------

    _statement: $ => choice(
      $.declaration,
      $.expression,
    ),

    declaration: $ => choice(
      $.variable_decl,
      $.type_decl,
    ),

    variable_decl: $ => seq(
      choice('let', 'var'),
      $.identifier,
      optional(seq(':', $.type_expr)),
      optional(seq('=', $.expression))
    ),

    type_decl: $ => seq(
      'type',
      $.identifier,
      optional(seq('[', $.type_param_list, ']'))
    ),

    type_param_list: $ => seq(
      $.identifier,
      repeat(seq(',', $.identifier))
    ),

    // -----------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------

    type_expr: $ => choice(
      $.lambda_type,
      seq($.identifier, optional(seq('[', $.type_list, ']')))
    ),

    lambda_type: $ => seq(
      '(', optional($.type_list), ')',
      '->',
      $.type_expr
    ),

    type_list: $ => seq(
      $.type_expr,
      repeat(seq(',', $.type_expr))
    ),

    // -----------------------------------------------------------------------
    // Expressions
    //
    // call is left-recursive: the expression grammar from the EBNF says:
    //   call ::= expression ('.' identifier)? ('[' type_list ']')? ('(' arg_list? ')')? lambda?
    //
    // Each optional suffix is a separate prec.left rule so the parser
    // can chain them: foo.bar[T](x) λ
    // -----------------------------------------------------------------------

    expression: $ => choice(
      $.lambda,
      $.if_expr,
      $.binary_expr,
      $.unary_expr,
      $.call,
      $.literal,
      $.identifier,
      seq('(', $.expression, ')')
    ),

    // call ::= expression ('.' identifier)? ('[' type_list ']')? ('(' arg_list? ')')? lambda?
    // We model each optional suffix as a separate left-recursive rule to
    // allow arbitrary chaining like: expr.field[T](args) { ... }
    call: $ => prec.left(10, seq(
      $.expression,
      choice(
        seq('.', $.identifier),               // member access
        seq('[', $.type_list, ']'),           // type application
        seq('(', optional($.arg_list), ')'),  // function call
        $.lambda,                             // trailing lambda
      )
    )),

    // if expr ':' block
    if_expr: $ => seq(
      'if',
      $.expression,
      ':',
      $.block
    ),

    // lambda ::= ('(' param_list? ')')? ('->' type_expr)? ':' block
    lambda: $ => seq(
      optional(seq('(', optional($.param_list), ')')),
      optional(seq('->', $.type_expr)),
      ':',
      $.block
    ),

    block: $ => seq(
      $._indent,
      repeat1($._statement),
      $._dedent
    ),

    // -----------------------------------------------------------------------
    // Binary / Unary
    // -----------------------------------------------------------------------

    binary_expr: $ => choice(
      // Arithmetic  (* / % bind tightest, then + -, then comparisons, then logical)
      prec.left(7, seq($.expression, choice('*', '/', '%'), $.expression)),
      prec.left(6, seq($.expression, choice('+', '-'), $.expression)),
      prec.left(5, seq($.expression, choice('<', '>', '<=', '>='), $.expression)),
      prec.left(4, seq($.expression, choice('==', '!='), $.expression)),
      prec.left(3, seq($.expression, 'and', $.expression)),
      prec.left(2, seq($.expression, 'or', $.expression)),
      prec.right(1, seq($.expression, '=', $.expression)),  // assignment
      prec.left(8, seq($.expression, $.custom_op, $.expression)), // custom ops
    ),

    unary_expr: $ => prec(9, seq(
      $.unary_op,
      $.expression
    )),

    unary_op: _ => choice('not', '-'),

    // Custom operators: any sequence of operator symbols not matching a built-in
    // (registered via the operator macro at compile time)
    custom_op: _ => token(prec(-1, /[!@#$%^&*\-+|<>?/\\~]+/)),

    // -----------------------------------------------------------------------
    // Params & Args
    // -----------------------------------------------------------------------

    param_list: $ => seq(
      $.param,
      repeat(seq(',', $.param)),
      optional(seq('...', $.identifier))
    ),

    param: $ => seq(
      $.identifier,
      optional(seq(':', $.type_expr))
    ),

    arg_list: $ => seq(
      $.arg,
      repeat(seq(',', $.arg))
    ),

    // arg ::= (identifier ':')? expression   -- named or positional
    arg: $ => seq(
      optional(seq(field('name', $.identifier), ':')),
      field('value', $.expression)
    ),

    // -----------------------------------------------------------------------
    // Literals
    // -----------------------------------------------------------------------

    literal: $ => choice(
      $.string_lit,
      $.number_lit,
      $.bool_lit,
      $.unit_lit,
      $.collection_lit,
    ),

    // string_lit ::= '"' char* '"'
    // Handled as a single token to avoid external scanner interaction
    string_lit: _ => token(seq(
      '"',
      repeat(choice(
        /[^"\\]+/,   // any non-quote, non-backslash char
        /\\./,        // escape sequence
      )),
      '"'
    )),

    // number_lit ::= digit+ ('.' digit+)?
    // The leading '-' is NOT part of the literal — it's handled by unary_expr
    number_lit: _ => /[0-9]+(\.[0-9]+)?/,

    bool_lit: _ => choice('true', 'false'),

    // unit_lit ::= 'discard'
    unit_lit: _ => 'discard',

    // collection_lit ::= '[' (expression (',' expression)*)? ']'
    collection_lit: $ => seq(
      '[',
      optional(seq(
        $.expression,
        repeat(seq(',', $.expression))
      )),
      ']'
    ),

    // -----------------------------------------------------------------------
    // Identifiers
    // identifier ::= letter (letter | digit | '_')*
    // letter     ::= [a-zA-Z] | '_'
    // -----------------------------------------------------------------------
    identifier: _ => /[a-zA-Z_][a-zA-Z0-9_]*/,
  }
});
