import 'dart:convert';

/// Validates that [config] is a valid Xray JSON object.
///
/// The payload must decode to a map and include a non-empty `outbounds` list.
/// Throws [ArgumentError] when validation fails.
void validateXrayConfig(String config) {
  try {
    final dynamic decoded = jsonDecode(config);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException();
    }

    final dynamic outbounds = decoded['outbounds'];
    if (outbounds is! List || outbounds.isEmpty) {
      throw ArgumentError(
        'The provided config must contain at least one outbound.',
      );
    }
  } on ArgumentError {
    rethrow;
  } catch (_) {
    throw ArgumentError(
      'The provided config must be a valid Xray JSON object with at least one outbound.',
    );
  }
}
