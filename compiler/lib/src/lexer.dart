enum TokenType {
  // Keywords
  kwLibrary,
  kwImport,
  kwAs,
  kwLet,
  kwVar,
  kwType,
  kwTrue,
  kwFalse,
  kwDiscard,
  kwAnd,
  kwOr,
  kwNot,
  kwIf,

  // Single-character tokens
  lParen,
  rParen,
  lBracket,
  rBracket,
  comma,
  dot,
  colon,
  minus,
  plus,
  slash,
  star,
  modulo,
  arrow, // For "->"
  // One or two character tokens
  bangEq,
  eq,
  eqEq,
  greater,
  greaterEq,
  less,
  lessEq,

  // Literals
  identifier,
  stringLit,
  numberLit,

  // Structural
  indent,
  dedent,
  eof,
}

class Token {
  const Token(this.type, this.lexeme, this.start, this.end);

  final TokenType type;
  final String lexeme;

  // start incl
  final (int, int) start;

  int get line => start.$1;

  // end excl
  final (int, int) end;

  @override
  String toString() => '$type("$lexeme") [${start.$1}:${start.$2}]';
}

class Lexer {
  Lexer(this._source);

  final String _source;
  final List<Token> _tokens = [];

  int _start = 0;
  int _current = 0;
  int _line = 1;
  int _column = 1;

  (int, int) get cursor => (_line, _column);

  final List<int> _indentStack = [0];

  List<Token> tokenize() {
    while (!_isAtEnd()) {
      _start = _current;
      _scanToken();
    }

    // Clean up remaining indents at end of file
    while (_indentStack.length > 1) {
      _indentStack.removeLast();
      _addToken(TokenType.dedent);
    }

    _tokens.add(Token(TokenType.eof, "", cursor, cursor));
    return _tokens;
  }

  void _scanToken() {
    String c = _advance();

    switch (c) {
      case '#':
        while (_peek() != '\n' && !_isAtEnd()) {
          _advance();
        }
        break;
      case '(':
        _addToken(TokenType.lParen);
        break;
      case ')':
        _addToken(TokenType.rParen);
        break;
      case '[':
        _addToken(TokenType.lBracket);
        break;
      case ']':
        _addToken(TokenType.rBracket);
        break;
      case ',':
        _addToken(TokenType.comma);
        break;
      case '.':
        _addToken(TokenType.dot);
        break;
      case ':':
        _addToken(TokenType.colon);
        break;
      case '-':
        _addToken(_match('>') ? TokenType.arrow : TokenType.minus);
        break;
      case '+':
        _addToken(TokenType.plus);
        break;
      case '*':
        _addToken(TokenType.star);
        break;
      case '/':
        _addToken(TokenType.slash);
        break;
      case '%':
        _addToken(TokenType.modulo);
        break;

      // Two-character operators
      case '!':
        _addToken(
          _match('=') ? TokenType.bangEq : throw Exception("Unexpected '!'"),
        );
        break;
      case '=':
        _addToken(_match('=') ? TokenType.eqEq : TokenType.eq);
        break;
      case '<':
        _addToken(_match('=') ? TokenType.lessEq : TokenType.less);
        break;
      case '>':
        _addToken(_match('=') ? TokenType.greaterEq : TokenType.greater);
        break;

      // Whitespace & Structural
      case ' ':
      case '\r':
      case '\t':
        // Ignore inline whitespace
        break;
      case '\n':
        _handleIndentation();
        break;

      // Literals
      case '"':
        _readString();
        break;

      default:
        if (_isDigit(c)) {
          _readNumber();
        } else if (_isAlpha(c)) {
          _readIdentifier();
        } else {
          throw Exception(
            "Lexer Error: Unexpected character '$c' at line $_line, col $_column",
          );
        }
    }
  }

  // --- Worker Methods ---

  void _readString() {
    while (_peek() != '"' && !_isAtEnd()) {
      if (_peek() == '\n') _line++;
      _advance();
    }

    if (_isAtEnd()) {
      throw Exception("Lexer Error: Unterminated string.");
    }

    _advance(); // The closing "
    String value = _source.substring(_start + 1, _current - 1);
    _addToken(TokenType.stringLit, value);
  }

  void _readNumber() {
    while (!_isAtEnd() && _isDigit(_peek())) {
      _advance();
    }

    // Fraction
    if (_peek() == '.' && _isDigit(_peekNext())) {
      _advance();
      while (!_isAtEnd() && _isDigit(_peek())) {
        _advance();
      }
    }

    _addToken(TokenType.numberLit, _source.substring(_start, _current));
  }

  void _readIdentifier() {
    while (!_isAtEnd() && _isAlphaNumeric(_peek())) {
      _advance();
    }

    String text = _source.substring(_start, _current);
    TokenType type = _getReservedKeyword(text) ?? TokenType.identifier;

    _addToken(type, type == TokenType.identifier ? text : "");
  }

  // --- The Tricky Part: Significant Whitespace ---

  void _handleIndentation() {
    _line++;
    _column = 1;

    int spaceCount = 0;
    while (_peek() == ' ' || _peek() == '\t') {
      spaceCount += _peek() == '\t' ? 4 : 1; // Count tabs as 4 spaces
      _advance();
    }

    // Ignore blank lines completely
    if (_peek() == '\n' || _isAtEnd()) return;

    if (spaceCount > _indentStack.last) {
      _indentStack.add(spaceCount);
      _addToken(TokenType.indent);
    } else if (spaceCount < _indentStack.last) {
      while (_indentStack.last > spaceCount) {
        _indentStack.removeLast();
        _addToken(TokenType.dedent);
      }
      if (_indentStack.last != spaceCount) {
        throw Exception(
          "Lexer Error: Inconsistent indentation at line $_line.",
        );
      }
    }
  }

  // --- Navigation & Utility Helpers ---

  bool _isAtEnd() => _current >= _source.length;

  String _advance() {
    _column++;
    return _source[_current++];
  }

  bool _match(String expected) {
    if (_isAtEnd() || _source[_current] != expected) return false;
    _current++;
    _column++;
    return true;
  }

  String _peek() => _isAtEnd() ? '\0' : _source[_current];
  String _peekNext() =>
      _current + 1 >= _source.length ? '\0' : _source[_current + 1];

  bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
  bool _isAlpha(String c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
      c == '_';
  bool _isAlphaNumeric(String c) => _isAlpha(c) || _isDigit(c);

  void _addToken(TokenType type, [String lexeme = ""]) {
    String text = lexeme.isEmpty ? _source.substring(_start, _current) : lexeme;
    // Adjust column so it points to the START of the token, not the end.
    int startColumn = _column - (_current - _start);
    _tokens.add(Token(type, text, (_line, startColumn), cursor));
  }

  TokenType? _getReservedKeyword(String text) {
    const keywords = {
      "library": TokenType.kwLibrary,
      "import": TokenType.kwImport,
      "as": TokenType.kwAs,
      "let": TokenType.kwLet,
      "var": TokenType.kwVar,
      "type": TokenType.kwType,
      "true": TokenType.kwTrue,
      "false": TokenType.kwFalse,
      "discard": TokenType.kwDiscard,
      "and": TokenType.kwAnd,
      "or": TokenType.kwOr,
      "not": TokenType.kwNot,
      "if": TokenType.kwIf,
    };
    return keywords[text];
  }
}
