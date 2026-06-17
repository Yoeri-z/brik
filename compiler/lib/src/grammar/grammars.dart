// ==========================================
// Base Node & Sum Types
// ==========================================

sealed class ASTNode {
  const ASTNode({required this.start, required this.end});

  final (int, int) start;
  final (int, int) end;
}

sealed class Statement extends ASTNode {
  const Statement({required super.start, required super.end});
}

// declaration ::= variable_decl | type_decl
sealed class Declaration extends Statement {
  const Declaration({required super.start, required super.end});
}

// expression ::= lambda | if | call | binary_expr | unary_expr | literal | identifier | "(" expression ")"
sealed class Expression extends Statement {
  const Expression({required super.start, required super.end});
}

// type_expr ::= lambda_type | identifier ("[" type_list "]")?
sealed class TypeExpr extends ASTNode {
  const TypeExpr({required super.start, required super.end});
}

// ==========================================
// Top-Level & Structure
// ==========================================

// program ::= library_decl? import_decl* statement*
class Program extends ASTNode {
  const Program({
    this.libraryDecl,
    this.importDecls = const [],
    this.statements = const [],
    required super.start,
    required super.end,
  });

  final LibraryDecl? libraryDecl;
  final List<ImportDecl> importDecls;
  final List<Statement> statements;
}

// library_decl ::= "library" identifier
class LibraryDecl extends ASTNode {
  const LibraryDecl(this.name, {required super.start, required super.end});
  final Identifier name;
}

// import_decl ::= "import" module_path ("as" identifier)?
class ImportDecl extends ASTNode {
  const ImportDecl({
    required this.path,
    this.alias,
    required super.start,
    required super.end,
  });

  final ModulePath path;
  final Identifier? alias;
}

// module_path ::= identifier ("." identifier)*
class ModulePath extends ASTNode {
  const ModulePath(this.path, {required super.start, required super.end});
  final List<Identifier> path;
}

// block ::= INDENT statement* DEDENT
class Block extends ASTNode {
  const Block(this.statements, {required super.start, required super.end});
  final List<Statement> statements;
}

// ==========================================
// Declarations
// ==========================================

// variable_decl ::= ("let" | "var") identifier (":" type_expr)? ("=" expression)?
class VariableDecl extends Declaration {
  const VariableDecl({
    required this.isVar, // true for 'var', false for 'let'
    required this.name,
    this.type,
    this.initializer,
    required super.start,
    required super.end,
  });

  final bool isVar;
  final Identifier name;
  final TypeExpr? type;
  final Expression? initializer;
}

// type_decl ::= "type" identifier ("[" type_param_list "]")?
class TypeDecl extends Declaration {
  const TypeDecl({
    required this.name,
    this.typeParams = const [],
    required super.start,
    required super.end,
  });

  final Identifier name;
  final List<Identifier> typeParams;
}

// ==========================================
// Type Expressions
// ==========================================

// lambda_type ::= "(" type_list? ")" "-> " type_expr
class LambdaType extends TypeExpr {
  const LambdaType({
    this.paramTypes = const [],
    required this.returnType,
    required super.start,
    required super.end,
  });

  final List<TypeExpr> paramTypes;
  final TypeExpr returnType;
}

// identifier ("[" type_list "]")?
class NamedType extends TypeExpr {
  const NamedType({
    required this.name,
    this.typeArgs = const [],
    required super.start,
    required super.end,
  });

  final Identifier name;
  final List<TypeExpr> typeArgs;
}

// ==========================================
// Expressions
// ==========================================

// if ::= "if" expression ":" block
class IfExpr extends Expression {
  const IfExpr({
    required this.condition,
    required this.block,
    required super.start,
    required super.end,
  });

  final Expression condition;
  final Block block;
}

// lambda ::= ("(" param_list? ")")? ("->" type_expr)? ":" block
class LambdaExpr extends Expression {
  const LambdaExpr({
    this.params = const [],
    this.restParam, // from ("..." identifier)?
    this.returnType,
    required this.block,
    required super.start,
    required super.end,
  });

  final List<Param> params;
  final Identifier? restParam;
  final TypeExpr? returnType;
  final Block block;
}

// call ::= expression ("." identifier)? ("[" type_list "]")? ("(" arg_list? ")")? lambda?
class CallExpr extends Expression {
  const CallExpr({
    required this.callee,
    this.member,
    this.typeArgs = const [],
    this.args = const [],
    this.trailingLambda,
    required super.start,
    required super.end,
  });

  final Expression callee;
  final Identifier? member;
  final List<TypeExpr> typeArgs;
  final List<Arg> args;
  final LambdaExpr? trailingLambda;
}

// binary_expr ::= expression operator expression
class BinaryExpr extends Expression {
  const BinaryExpr({
    required this.left,
    required this.operator,
    required this.right,
    required super.start,
    required super.end,
  });

  final Expression left;
  final String operator; // e.g., "+", "and", or "<CUSTOM_OP>"
  final Expression right;
}

// unary_expr ::= unary_op expression
class UnaryExpr extends Expression {
  const UnaryExpr({
    required this.operator,
    required this.operand,
    required super.start,
    required super.end,
  });

  final String operator; // e.g., "not", "-"
  final Expression operand;
}

// "(" expression ")"
class GroupedExpr extends Expression {
  const GroupedExpr(
    this.expression, {
    required super.start,
    required super.end,
  });
  final Expression expression;
}

// identifier ::= letter (letter | digit | "_")*
class Identifier extends Expression {
  const Identifier(this.symbol, {required super.start, required super.end});
  final String symbol;
}

// ==========================================
// Parameters & Arguments
// ==========================================

// param ::= identifier (":" type_expr)?
class Param extends ASTNode {
  const Param({
    required this.name,
    this.type,
    required super.start,
    required super.end,
  });

  final Identifier name;
  final TypeExpr? type;
}

// arg ::= (identifier ":")? expression
class Arg extends ASTNode {
  const Arg({
    this.name, // Will be non-null if named argument
    required this.value,
    required super.start,
    required super.end,
  });

  final Identifier? name;
  final Expression value;
}

// ==========================================
// Literals (All inherit from Expression)
// ==========================================

sealed class LiteralExpr extends Expression {
  const LiteralExpr({required super.start, required super.end});
}

class StringLit extends LiteralExpr {
  const StringLit(this.value, {required super.start, required super.end});
  final String value;
}

class NumberLit extends LiteralExpr {
  const NumberLit(this.value, {required super.start, required super.end});
  // Storing as String prevents precision loss during parsing
  // You can cast it to num/double in your analysis phase
  final String value;
}

class BoolLit extends LiteralExpr {
  const BoolLit(this.value, {required super.start, required super.end});
  final bool value;
}

class UnitLit extends LiteralExpr {
  const UnitLit({
    required super.start,
    required super.end,
  }); // Represents "discard"
}

class CollectionLit extends LiteralExpr {
  const CollectionLit({
    this.items = const [],
    required super.start,
    required super.end,
  });
  final List<Expression> items;
}
