/// Coarse buckets only. The raw duration is never stored or logged.
String symptomDurationBucket(int durationMs) {
  if (durationMs < 15000) return '0_15';
  if (durationMs < 30000) return '15_30';
  if (durationMs < 60000) return '30_60';
  return '60_plus';
}
