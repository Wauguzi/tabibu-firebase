// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'region_read_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RegionReadResult {

 String get impression; List<String> get features; RegionUncertainty get uncertainty; String get caveat;
/// Create a copy of RegionReadResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RegionReadResultCopyWith<RegionReadResult> get copyWith => _$RegionReadResultCopyWithImpl<RegionReadResult>(this as RegionReadResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RegionReadResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RegionReadResult&&(identical(other.impression, _this.impression) || other.impression == _this.impression)&&const DeepCollectionEquality().equals(other.features, _this.features)&&(identical(other.uncertainty, _this.uncertainty) || other.uncertainty == _this.uncertainty)&&(identical(other.caveat, _this.caveat) || other.caveat == _this.caveat));
}


@override
int get hashCode {
  final _this = this as RegionReadResult;
  return Object.hash(runtimeType,_this.impression,const DeepCollectionEquality().hash(_this.features),_this.uncertainty,_this.caveat);
}

@override
String toString() {
  final _this = this as RegionReadResult;
  return 'RegionReadResult(impression: ${_this.impression}, features: ${_this.features}, uncertainty: ${_this.uncertainty}, caveat: ${_this.caveat})';
}


}

/// @nodoc
abstract mixin class $RegionReadResultCopyWith<$Res>  {
  factory $RegionReadResultCopyWith(RegionReadResult value, $Res Function(RegionReadResult) _then) = _$RegionReadResultCopyWithImpl;
@useResult
$Res call({
 String impression, List<String> features, RegionUncertainty uncertainty, String caveat
});




}
/// @nodoc
class _$RegionReadResultCopyWithImpl<$Res>
    implements $RegionReadResultCopyWith<$Res> {
  _$RegionReadResultCopyWithImpl(this._self, this._then);

  final RegionReadResult _self;
  final $Res Function(RegionReadResult) _then;

/// Create a copy of RegionReadResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? impression = null,Object? features = null,Object? uncertainty = null,Object? caveat = null,}) {
  return _then(RegionReadResult(
impression: null == impression ? _self.impression : impression // ignore: cast_nullable_to_non_nullable
as String,features: null == features ? _self.features : features // ignore: cast_nullable_to_non_nullable
as List<String>,uncertainty: null == uncertainty ? _self.uncertainty : uncertainty // ignore: cast_nullable_to_non_nullable
as RegionUncertainty,caveat: null == caveat ? _self.caveat : caveat // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RegionReadResult].
extension RegionReadResultPatterns on RegionReadResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RegionReadResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RegionReadResult() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RegionReadResult value)  $default,){
final _that = this;
switch (_that) {
case _RegionReadResult():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RegionReadResult value)?  $default,){
final _that = this;
switch (_that) {
case _RegionReadResult() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String impression,  List<String> features,  RegionUncertainty uncertainty,  String caveat)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RegionReadResult() when $default != null:
return $default(_that.impression,_that.features,_that.uncertainty,_that.caveat);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String impression,  List<String> features,  RegionUncertainty uncertainty,  String caveat)  $default,) {final _that = this;
switch (_that) {
case _RegionReadResult():
return $default(_that.impression,_that.features,_that.uncertainty,_that.caveat);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String impression,  List<String> features,  RegionUncertainty uncertainty,  String caveat)?  $default,) {final _that = this;
switch (_that) {
case _RegionReadResult() when $default != null:
return $default(_that.impression,_that.features,_that.uncertainty,_that.caveat);case _:
  return null;

}
}

}

/// @nodoc


class _RegionReadResult extends RegionReadResult {
  const _RegionReadResult({required this.impression, required  List<String> features, required this.uncertainty, required this.caveat}): _features = features,super._();
  

@override final  String impression;
 final  List<String> _features;
@override List<String> get features {
  if (_features is EqualUnmodifiableListView) return _features;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_features);
}

@override final  RegionUncertainty uncertainty;
@override final  String caveat;

/// Create a copy of RegionReadResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RegionReadResultCopyWith<_RegionReadResult> get copyWith => __$RegionReadResultCopyWithImpl<_RegionReadResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RegionReadResult&&(identical(other.impression, impression) || other.impression == impression)&&const DeepCollectionEquality().equals(other.features, _features)&&(identical(other.uncertainty, uncertainty) || other.uncertainty == uncertainty)&&(identical(other.caveat, caveat) || other.caveat == caveat));
}


@override
int get hashCode {
    return Object.hash(runtimeType,impression,const DeepCollectionEquality().hash(_features),uncertainty,caveat);
}

@override
String toString() {
    return 'RegionReadResult(impression: $impression, features: $features, uncertainty: $uncertainty, caveat: $caveat)';
}


}

/// @nodoc
abstract mixin class _$RegionReadResultCopyWith<$Res> implements $RegionReadResultCopyWith<$Res> {
  factory _$RegionReadResultCopyWith(_RegionReadResult value, $Res Function(_RegionReadResult) _then) = __$RegionReadResultCopyWithImpl;
@override @useResult
$Res call({
 String impression, List<String> features, RegionUncertainty uncertainty, String caveat
});




}
/// @nodoc
class __$RegionReadResultCopyWithImpl<$Res>
    implements _$RegionReadResultCopyWith<$Res> {
  __$RegionReadResultCopyWithImpl(this._self, this._then);

  final _RegionReadResult _self;
  final $Res Function(_RegionReadResult) _then;

/// Create a copy of RegionReadResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? impression = null,Object? features = null,Object? uncertainty = null,Object? caveat = null,}) {
  return _then(_RegionReadResult(
impression: null == impression ? _self.impression : impression // ignore: cast_nullable_to_non_nullable
as String,features: null == features ? _self._features : features // ignore: cast_nullable_to_non_nullable
as List<String>,uncertainty: null == uncertainty ? _self.uncertainty : uncertainty // ignore: cast_nullable_to_non_nullable
as RegionUncertainty,caveat: null == caveat ? _self.caveat : caveat // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
