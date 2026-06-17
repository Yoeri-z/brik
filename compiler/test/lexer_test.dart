import 'package:test/test.dart';
import 'package:compiler/src/lexer.dart';

void main() {
  // --- Helpers ---
  // Strips EOF to make standard syntax assertions much cleaner
  List<TokenType> getTypes(String source) {
    final tokens = Lexer(source).tokenize();
    return tokens
        .where((t) => t.type != TokenType.eof)
        .map((t) => t.type)
        .toList();
  }

  // --- 1. Exhaustive Table-Driven Syntax Tests ---
  group('Lexer | Syntax Definitions |', () {
    // Dart 3 Record: (Test Name, Source Code, Expected Token Types)
    final syntaxCases = [
      // Keywords
      (
        'Decl Keywords',
        'let var type',
        [TokenType.kwLet, TokenType.kwVar, TokenType.kwType],
      ),
      (
        'Module Keywords',
        'library import as',
        [TokenType.kwLibrary, TokenType.kwImport, TokenType.kwAs],
      ),
      (
        'Logic Keywords',
        'true false and or not',
        [
          TokenType.kwTrue,
          TokenType.kwFalse,
          TokenType.kwAnd,
          TokenType.kwOr,
          TokenType.kwNot,
        ],
      ),

      // Punctuation & Grouping
      (
        'Brackets',
        '() []',
        [
          TokenType.lParen,
          TokenType.rParen,
          TokenType.lBracket,
          TokenType.rBracket,
        ],
      ),
      (
        'Separators',
        ', . :',
        [TokenType.comma, TokenType.dot, TokenType.colon],
      ),

      // Operators
      (
        'Math Operators',
        '+ - * / %',
        [
          TokenType.plus,
          TokenType.minus,
          TokenType.star,
          TokenType.slash,
          TokenType.modulo,
        ],
      ),
      (
        'Comparison',
        '== != < > <= >=',
        [
          TokenType.eqEq,
          TokenType.bangEq,
          TokenType.less,
          TokenType.greater,
          TokenType.lessEq,
          TokenType.greaterEq,
        ],
      ),
      ('Assignment & Arrow', '= ->', [TokenType.eq, TokenType.arrow]),

      // Complex Lexemes
      (
        'Identifiers',
        'foo bar_baz _hidden',
        [TokenType.identifier, TokenType.identifier, TokenType.identifier],
      ),
      (
        'Numbers',
        '42 3.14 -7',
        [
          TokenType.numberLit,
          TokenType.numberLit,
          TokenType.minus,
          TokenType.numberLit,
        ],
      ),
      (
        'Strings',
        '"hello" "with space"',
        [TokenType.stringLit, TokenType.stringLit],
      ),
    ];

    for (final tc in syntaxCases) {
      test(tc.$1, () => expect(getTypes(tc.$2), equals(tc.$3)));
    }
  });

  // --- 2. Positional and Lexeme Integrity ---
  group('Lexer | Token Metadata Integrity |', () {
    test('Accurately tracks line, column, and extracted values', () {
      final source = 'let foo = 42\n"hello"';
      final tokens = Lexer(source).tokenize();

      // Ensure exact metadata mapping
      final expectedTokens = [
        (type: TokenType.kwLet, lexeme: 'let', line: 1, col: 1),
        (type: TokenType.identifier, lexeme: 'foo', line: 1, col: 5),
        (type: TokenType.eq, lexeme: '=', line: 1, col: 9),
        (type: TokenType.numberLit, lexeme: '42', line: 1, col: 11),
        (
          type: TokenType.stringLit,
          lexeme: 'hello',
          line: 2,
          col: 1,
        ), // Note: Quotes stripped
        (type: TokenType.eof, lexeme: '', line: 2, col: 8),
      ];

      expect(tokens.length, equals(expectedTokens.length));

      for (int i = 0; i < tokens.length; i++) {
        expect(tokens[i].type, equals(expectedTokens[i].type));
        expect(tokens[i].lexeme, equals(expectedTokens[i].lexeme));
        expect(tokens[i].start.$1, equals(expectedTokens[i].line));
        expect(tokens[i].start.$2, equals(expectedTokens[i].col));
      }
    });
  });

  // --- 3. Significant Whitespace Engine ---
  group('Lexer | Block Indentation |', () {
    test('Injects INDENT and DEDENT correctly based on Pythonic spacing', () {
      final source = '''
if true:
    foo()
    bar()
baz()
''';
      // We only care about the structural tokens for this test
      final structuralTypes = Lexer(source)
          .tokenize()
          .where(
            (t) => [
              TokenType.indent,
              TokenType.dedent,
              TokenType.identifier,
            ].contains(t.type),
          )
          .map((t) => t.type)
          .toList();

      expect(
        structuralTypes,
        equals([
          // 'if true:' ignored by filter
          TokenType.indent, // 4 spaces injected
          TokenType.identifier, // foo
          TokenType.identifier, // bar
          TokenType.dedent, // drop back to 0 spaces
          TokenType.identifier, // baz
        ]),
      );
    });

    test('Cleans up unclosed indents at EOF', () {
      final source = 'block:\n    open()';
      final tokens = Lexer(source).tokenize();

      // The last two tokens MUST be dedent, then EOF
      expect(tokens[tokens.length - 2].type, equals(TokenType.dedent));
      expect(tokens.last.type, equals(TokenType.eof));
    });
  });

  // --- 4. Edge Cases & Error Recovery ---
  group('Lexer | Edge Cases & Exceptions |', () {
    final errorCases = [
      ('Unterminated String', '"missing closing quote', 'Unterminated string'),
      ('Invalid Character', 'let x = @;', 'Unexpected character'),
      (
        'Inconsistent Indentation',
        'block:\n    foo()\n  bar()',
        'Inconsistent indentation',
      ),
    ];

    for (final tc in errorCases) {
      test('Throws on ${tc.$1}', () {
        final lexer = Lexer(tc.$2);
        // We expect an Exception, and its message should contain the exact error reason
        expect(
          () => lexer.tokenize(),
          throwsA(
            predicate((e) => e is Exception && e.toString().contains(tc.$3)),
          ),
        );
      });
    }
  });
}
