// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension InitializeRequestChecks on Subject<InitializeRequest> {
  Subject<ProtocolVersion?> get protocolVersion =>
      has((x) => x.protocolVersion, 'protocolVersion');
  Subject<ClientCapabilities> get capabilities =>
      has((x) => x.capabilities, 'capabilities');
  Subject<Implementation> get clientInfo =>
      has((x) => x.clientInfo, 'clientInfo');
}

extension InitializeResultChecks on Subject<InitializeResult> {
  Subject<ProtocolVersion?> get protocolVersion =>
      has((x) => x.protocolVersion, 'protocolVersion');
  Subject<ServerCapabilities> get capabilities =>
      has((x) => x.capabilities, 'capabilities');
  Subject<Implementation> get serverInfo =>
      has((x) => x.serverInfo, 'serverInfo');
  Subject<String?> get instructions =>
      has((x) => x.instructions, 'instructions');
}

extension ClientCapabilitiesChecks on Subject<ClientCapabilities> {
  Subject<Map<String, Object?>?> get experimental =>
      has((x) => x.experimental, 'experimental');
  Subject<RootsCapabilities?> get roots => has((x) => x.roots, 'roots');
  Subject<Map<String, Object?>?> get sampling =>
      has((x) => x.sampling, 'sampling');
  Subject<ElicitationCapability?> get elicitation =>
      has((x) => x.elicitation, 'elicitation');
}

extension RootsCapabilitiesChecks on Subject<RootsCapabilities> {
  Subject<bool?> get listChanged => has((x) => x.listChanged, 'listChanged');
}

extension ElicitationCapabilityChecks on Subject<ElicitationCapability> {
  Subject<Map<String, Object?>?> get form => has((x) => x.form, 'form');
  Subject<Map<String, Object?>?> get url => has((x) => x.url, 'url');
}

extension ServerCapabilitiesChecks on Subject<ServerCapabilities> {
  Subject<Map<String, Object?>?> get experimental =>
      has((x) => x.experimental, 'experimental');
  Subject<Completions?> get completions =>
      has((x) => x.completions, 'completions');
  Subject<Logging?> get logging => has((x) => x.logging, 'logging');
  Subject<Prompts?> get prompts => has((x) => x.prompts, 'prompts');
  Subject<Resources?> get resources => has((x) => x.resources, 'resources');
  Subject<Tools?> get tools => has((x) => x.tools, 'tools');
}

extension PromptsChecks on Subject<Prompts> {
  Subject<bool?> get listChanged => has((x) => x.listChanged, 'listChanged');
}

extension ResourcesChecks on Subject<Resources> {
  Subject<bool?> get listChanged => has((x) => x.listChanged, 'listChanged');
  Subject<bool?> get subscribe => has((x) => x.subscribe, 'subscribe');
}

extension ToolsChecks on Subject<Tools> {
  Subject<bool?> get listChanged => has((x) => x.listChanged, 'listChanged');
}

extension ImplementationChecks on Subject<Implementation> {
  Subject<String> get version => has((x) => x.version, 'version');
  Subject<String?> get description => has((x) => x.description, 'description');
  Subject<List<Icon>?> get icons => has((x) => x.icons, 'icons');
  Subject<String?> get websiteUrl => has((x) => x.websiteUrl, 'websiteUrl');
}
