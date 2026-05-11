import 'dart:async';

/// Interface for showing dialogs.
abstract interface class DialogSupport {
  /// Shows a single select dialog with the given [options].
  ///
  /// Returns the index of the selected option, or null if the dialog was
  /// cancelled or not implemented.
  ///
  /// The [title] will be shown in an implementation specific way if given.
  Future<int?> showSingleSelectDialog(List<String> options, {String? title});

  /// Shows a multi select dialog with the given [options].
  ///
  /// Returns the indices of the selected options, or null if the dialog was
  /// cancelled or not implemented.
  ///
  /// The [title] will be shown in an implementation specific way if given.
  Future<Set<int>?> showMultiSelectDialog(List<String> options,
      {String? title});
}
