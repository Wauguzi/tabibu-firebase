import 'package:flutter_test/flutter_test.dart';
import 'package:tabibu/features/appointments/symptom_duration.dart';

void main() {
  test('duration buckets never keep the raw length', () {
    expect(symptomDurationBucket(0), '0_15');
    expect(symptomDurationBucket(14999), '0_15');
    expect(symptomDurationBucket(15000), '15_30');
    expect(symptomDurationBucket(29999), '15_30');
    expect(symptomDurationBucket(30000), '30_60');
    expect(symptomDurationBucket(59999), '30_60');
    expect(symptomDurationBucket(60000), '60_plus');
  });
}
