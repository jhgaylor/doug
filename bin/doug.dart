import 'package:args/args.dart';
import 'package:mcp_dart/mcp_dart.dart';
import 'package:doug/doug.dart';
import 'dart:io';

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
    ..addFlag('version', negatable: false, help: 'Print the tool version.')
    ..addOption(
      'transport',
      allowed: ['http', 'stdio'],
      help: 'Transport method to use (http or stdio).',
      mandatory: true,
    )
    ..addOption(
      'url',
      help: 'URL to connect to. Required if transport is http.',
    )
    ..addOption(
      'command',
      help: 'Command to execute. Required if transport is stdio.',
    )
    ..addOption(
      'args',
      help: 'Arguments for the command. Required if transport is stdio.',
    );
}

void printUsage(ArgParser argParser) {
  print('Usage: dart dart_mcp_client.dart <flags> [arguments]');
  print(argParser.usage);
}

Future<void> main(List<String> arguments) async {
  final ArgParser argParser = buildParser();
  try {
    final ArgResults results = argParser.parse(arguments);
    bool verbose = false;

    // Process the parsed arguments.
    if (results.flag('help')) {
      printUsage(argParser);
      return;
    }
    if (results.flag('version')) {
      print('dart_mcp_client version: $version');
      return;
    }
    if (results.flag('verbose')) {
      verbose = true;
    }

    // Validate transport-dependent arguments
    final String transport = results['transport'] as String;
    
    if (transport == 'http') {
      final String? url = results['url'] as String?;
      if (url == null) {
        throw FormatException('--url is required when transport is http');
      }
    } else if (transport == 'stdio') {
      final String? command = results['command'] as String?;
      if (command == null) {
        throw FormatException('--command is required when transport is stdio');
      }
      final String? args = results['args'] as String?;
      if (args == null) {
        throw FormatException('--args is required when transport is stdio');
      }
    }
  

    late final Doug doug = Doug();

    if (transport == 'http') {
      final String url = results['url'] as String;
      await doug.addHttpClient(url);
    } else if (transport == 'stdio') {
      final String command = results['command'] as String;
      final String args = results['args'] as String;
      await doug.addStdioClient(command, args);
    }

    final clientCapabilities = await doug.getClientCapabilities();
    final resources = await doug.getResourceValues(["candidate-info://resume-url"]);
    await doug.close();
    print(clientCapabilities.map((e) => e.toJson()));
    print("Resources: ${resources.map((e) => e.toJson())}");
    exit(0);
  } on FormatException catch (e) {
    // Print usage information if an invalid argument was provided.
    print(e.message);
    print('');
    printUsage(argParser);
  }
}
