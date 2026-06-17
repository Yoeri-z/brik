import 'package:compiler/src/grammar/grammars.dart';
import 'package:compiler/src/lexer.dart';
import 'package:compiler/src/utils/errors.dart';
import 'package:path/path.dart';

class Parser {
  Parser(this._tokens);

  final List<Token> _tokens;

  int _cursor = 0;

  Token get _current => _tokens[_cursor];
  Token _advance() => _tokens[_cursor++];

  bool _match(TokenType type) => _current.type == type;

  Program parseProgram() {
    LibraryDecl? libraryDecl;
    List<ImportDecl> importDecls = [];
    List<Statement> statements = [];

    if (_match(.kwLibrary)) libraryDecl = _parseLibrary();

    while (_match(TokenType.kwImport)) {
      importDecls.add(_parseImport());
    }

    while (!_match(TokenType.eof)) {
      statements.add(_parseStatement());
    }

    return Program(
      start: (0, 0),
      end: _current.start,
      libraryDecl: libraryDecl,
      importDecls: importDecls,
      statements: statements,
    );
  }

  LibraryDecl _parseLibrary() {
    final start = _advance().start;
    final ident = _advance();

    if (ident.type != .identifier) {
      throw CompileError(
        'keyword `library` must be followed by an identifier',
        ident,
      );
    }

    enforceLineEnd(start.$1);

    return LibraryDecl(
      Identifier(ident.lexeme, start: ident.start, end: ident.end),
      start: start,
      end: ident.end,
    );
  }

  void enforceLineEnd(int line) {
    if (_current.start.$1 == line && _current.type != .eof) {
      throw CompileError('line must end', _current);
    }
  }

  ImportDecl _parseImport() {
    final start = _advance().start;
    final path = _parsePath();
    Identifier? alias;

    var end = path.end;

    if (_current.type == .kwAs) {
      _advance();
      final ident = _advance();
      if (ident.type != .identifier) {
        throw CompileError(
          '`as` keyword must be followed by an identifier',
          ident,
        );
      }

      alias = Identifier(ident.lexeme, start: start, end: end);
      end = ident.end;
    }

    enforceLineEnd(start.$1);

    return ImportDecl(path: path, alias: alias, start: start, end: end);
  }

  ModulePath _parsePath() {
    final identifiers = <Identifier>[];
    final first = _advance();

    if (first.type != .identifier) {
      throw CompileError(
        'Import statement must be followed by at least 1 identifier',
        first,
      );
    }

    identifiers.add(
      Identifier(first.lexeme, start: first.start, end: first.end),
    );

    while (_current.type == .dot) {
      _advance();
      final ident = _advance();

      if (ident.type != .identifier) {
        throw CompileError(
          'Import subpath `.` must be followed by at least 1 identifier',
          first,
        );
      }

      identifiers.add(
        Identifier(ident.lexeme, start: ident.start, end: ident.end),
      );
    }

    return ModulePath(
      identifiers,
      start: identifiers.first.start,
      end: identifiers.last.end,
    );
  }

  Statement _parseStatement() {
    throw UnimplementedError();
  }

  void debugPrintCurrent() {
    print(_current);
  }

  void debugPrintTokens() {
    print(_tokens);
  }
}
