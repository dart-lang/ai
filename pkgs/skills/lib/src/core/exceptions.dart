/// Exception that is thrown when the user aborts an operation.
class UserAbortException implements Exception {
  final String message;

  UserAbortException(this.message);

  @override
  String toString() => message;
}
