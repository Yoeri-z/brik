import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:compiler/src/lexer.dart';

const String version = '0.0.1';

ArgParser buildParser() {
  return ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show additional command output.',
    )
    ..addFlag('version', negatable: false, help: 'Print the tool version.');
}

void printUsage(ArgParser argParser) {
  print('Usage: dart compiler.dart <flags> [arguments]');
  print(argParser.usage);
}

void main(List<String> arguments) {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);

    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }
    if (results.flag('version')) {
      print('compiler version: $version');
      return;
    }

    final path = arguments.first;

    if (p.extension(path) != '.brik') {
      throw ArgumentError('Input file must be a brik file');
    }

    final brikCode = File.fromUri(p.toUri(path)).readAsStringSync();
    final lexer = Lexer(brikCode);

    final tokens = lexer.tokenize();

    print(tokens.join('\n'));
  } on FormatException catch (e) {
    print(e.message);
    print('');
    printUsage(argParser);
  }
}
