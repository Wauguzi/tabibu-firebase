import 'package:tabibu/core/helpers/db_helper.dart';

/// In-memory [DBHelper] with scriptable read/write failures and counters.
class FakeDbHelper implements DBHelper {
  final Map<String, Map<String, Object?>> boxes = {};
  bool failReads = false;
  bool failWrites = false;
  int getCalls = 0;
  int getAllCalls = 0;

  Map<String, Object?> _box(String name) =>
      boxes.putIfAbsent(name, () => <String, Object?>{});

  @override
  Future<void> put<T>(String boxName, String key, T value) async {
    if (failWrites) throw Exception('disk down');
    _box(boxName)[key] = value;
  }

  @override
  Future<void> putAll<T>(String boxName, Map<String, T> values) async {
    if (failWrites) throw Exception('disk down');
    _box(boxName).addAll(values);
  }

  @override
  Future<T?> get<T>(String boxName, String key) async {
    getCalls++;
    if (failReads) throw Exception('disk down');
    return _box(boxName)[key] as T?;
  }

  @override
  Future<List<T>> getAll<T>(String boxName) async {
    getAllCalls++;
    if (failReads) throw Exception('disk down');
    return _box(boxName).values.cast<T>().toList();
  }

  @override
  Future<void> delete<T>(String boxName, String key) async {
    if (failWrites) throw Exception('disk down');
    _box(boxName).remove(key);
  }

  @override
  Future<void> clearBox<T>(String boxName) async {
    _box(boxName).clear();
  }

  @override
  Future<void> deleteAll(Map<Type, String> names) async {
    names.values.forEach(boxes.remove);
  }
}
