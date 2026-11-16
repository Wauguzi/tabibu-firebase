import 'package:freezed_annotation/freezed_annotation.dart';

part 'region_read_result.freezed.dart';

/// How sure the region read is, exactly as the template reports it.
enum RegionUncertainty {
  low('low'),
  medium('medium'),
  high('high');

  const RegionUncertainty(this.wire);

  /// The template's word, or null for anything else.
  final String wire;

  static RegionUncertainty? fromWire(String? raw) => switch (raw) {
    'low' => .low,
    'medium' => .medium,
    'high' => .high,
    _ => null,
  };
}

/// A parsed slide-region read. Never written to the report.
@freezed
abstract class RegionReadResult with _$RegionReadResult {
  const factory RegionReadResult({
    required String impression,
    required List<String> features,
    required RegionUncertainty uncertainty,
    required String caveat,
  }) = _RegionReadResult;

  const RegionReadResult._();

  /// Parses template JSON, failing closed: a non-map, a missing or blank
  /// impression or caveat, a non-list of features, or an uncertainty outside
  /// low|medium|high rejects the whole read.
  static RegionReadResult? tryParse(Object? json) {
    if (json is! Map) return null;
    final impression = _nonBlank(json['impression']);
    final caveat = _nonBlank(json['caveat']);
    final features = json['features'];
    final uncertainty = RegionUncertainty.fromWire(
      json['uncertainty'] as String?,
    );
    if (impression == null ||
        caveat == null ||
        features is! List ||
        uncertainty == null) {
      return null;
    }
    final cleaned = <String>[];
    for (final feature in features) {
      if (feature is! String) return null;
      final line = feature.trim();
      if (line.isNotEmpty) cleaned.add(line);
    }
    return RegionReadResult(
      impression: impression,
      features: cleaned,
      uncertainty: uncertainty,
      caveat: caveat,
    );
  }

  static String? _nonBlank(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty ? null : text;
  }
}
