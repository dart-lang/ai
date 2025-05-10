library mcp_codegen;

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/mcp_generator.dart';

Builder mcpBuilder(BuilderOptions options) {
  return PartBuilder([MCPGenerator()], '.mcp.g.dart');
}
