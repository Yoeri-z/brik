import 'package:compiler/src/lexer.dart';

class CompileError implements Exception {
  final String message;
  final Token token;

  const CompileError(this.message, this.token);

  @override
  String toString() => 'CompileError: $message at ${token.start}';
}

class SourceReporter {
  const SourceReporter(this.source);

  final String source;

  void reportError(CompileError error) {
    final token = error.token;
    final lineNum = token.start.$1;
    final startCol = token.start.$2;
    final endCol = token.end.$2;

    // Split source into lines (1-indexed array adjustment)
    final lines = source.split('\n');
    if (lineNum <= 0 || lineNum > lines.length) {
      print('Error: ${error.message} (Location out of source bounds)');
      return;
    }

    final offendingLine = lines[lineNum - 1];

    // Build the underline string
    // Spaces up to the start column, then '^' up to the end column
    final padding = ' ' * (startCol - 1);

    // For zero-width tokens (like EOF), make the underline at least 1 character wide
    final length = (endCol - startCol) <= 0 ? 1 : (endCol - startCol);
    final underline = '^' * length;

    final indent = ' ' * lineNum.toString().length;

    print('--> Parse Error at line $lineNum, column $startCol');
    print('$indent |');
    print('$lineNum | $offendingLine');
    print('$indent | $padding$underline');
    print('Error: ${error.message}\n');
  }
}
