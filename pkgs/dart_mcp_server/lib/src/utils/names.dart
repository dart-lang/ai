// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A namespace for all the parameter names.
extension ParameterNames on Never {
  static const arguments = 'arguments';
  static const column = 'column';
  static const command = 'command';
  static const directory = 'directory';
  static const empty = 'empty';
  static const line = 'line';
  static const name = 'name';
  static const packageNames = 'packageNames';
  static const paths = 'paths';
  static const platform = 'platform';
  static const position = 'position';
  static const projectType = 'projectType';
  static const query = 'query';
  static const root = 'root';
  static const roots = 'roots';
  static const template = 'template';
  static const uri = 'uri';
  static const uris = 'uris';
  static const userJourney = 'user_journey';
}

/// The names of all the tools provided by the server.
enum ToolNames {
  addRoots('add_roots'),
  analyzeFiles('analyze_files'),
  connectDartToolingDaemon('connect_dart_tooling_daemon'),
  createProject('create_project'),
  dartFix('dart_fix'),
  dartFormat('dart_format'),
  flutterDriverCommand('flutter_driver_command'),
  getActiveLocation('get_active_location'),
  getAppLogs('get_app_logs'),
  getRuntimeErrors('get_runtime_errors'),
  getSelectedWidget('get_selected_widget'),
  getWidgetTree('get_widget_tree'),
  hotReload('hot_reload'),
  hotRestart('hot_restart'),
  hover('hover'),
  launchApp('launch_app'),
  listDevices('list_devices'),
  listRunningApps('list_running_apps'),
  pub('pub'),
  pubDevSearch('pub_dev_search'),
  readPackageUris('read_package_uris'),
  removeRoots('remove_roots'),
  resolveWorkspaceSymbol('resolve_workspace_symbol'),
  ripGrepPackages('rip_grep_packages'),
  runTests('run_tests'),
  setWidgetSelectionMode('set_widget_selection_mode'),
  signatureHelp('signature_help'),
  stopApp('stop_app'),
  takeScreenshot('take_screenshot');

  final String name;
  const ToolNames(this.name);

  @override
  String toString() => name;
}

/// The names of all the prompts provided by the server.
enum PromptNames {
  flutterDriverUserJourneyTest('flutter_driver_user_journey_test');

  final String name;
  const PromptNames(this.name);

  @override
  String toString() => name;
}
