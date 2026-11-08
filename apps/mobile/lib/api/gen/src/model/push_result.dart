//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/push_applied.dart';
import 'package:wambito/api/gen/src/model/sync_record.dart';
import 'package:wambito/api/gen/src/model/push_conflict.dart';
import 'package:wambito/api/gen/src/model/push_rejected.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/any_of.dart';

part 'push_result.g.dart';

/// PushResult
///
/// Properties:
/// * [id]
/// * [version]
/// * [conflict]
/// * [error] - `id_taken`: the id is someone else's. `not_found`: an update for a record the server does not have (never uploaded, or a purged tombstone); resync in full.
@BuiltValue()
abstract class PushResult implements Built<PushResult, PushResultBuilder> {
  /// Any Of [PushApplied], [PushConflict], [PushRejected]
  AnyOf get anyOf;

  PushResult._();

  factory PushResult([void updates(PushResultBuilder b)]) = _$PushResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PushResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PushResult> get serializer => _$PushResultSerializer();
}

class _$PushResultSerializer implements PrimitiveSerializer<PushResult> {
  @override
  final Iterable<Type> types = const [PushResult, _$PushResult];

  @override
  final String wireName = r'PushResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PushResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    PushResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final anyOf = object.anyOf;
    return serializers.serialize(
      anyOf,
      specifiedType: FullType(AnyOf, anyOf.types.map((type) => FullType(type)).toList()),
    )!;
  }

  @override
  PushResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PushResultBuilder();
    Object? anyOfDataSrc;
    final targetType = const FullType(AnyOf, [
      FullType(PushApplied),
      FullType(PushConflict),
      FullType(PushRejected),
    ]);
    anyOfDataSrc = serialized;
    result.anyOf = serializers.deserialize(anyOfDataSrc, specifiedType: targetType) as AnyOf;
    return result.build();
  }
}

/// `id_taken`: the id is someone else's. `not_found`: an update for a record the server does not have (never uploaded, or a purged tombstone); resync in full.
class PushResultErrorEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'id_taken')
  static const PushResultErrorEnum idTaken = _$pushResultErrorEnum_idTaken;
  @BuiltValueEnumConst(wireName: r'not_found')
  static const PushResultErrorEnum notFound = _$pushResultErrorEnum_notFound;

  static Serializer<PushResultErrorEnum> get serializer => _$pushResultErrorEnumSerializer;

  const PushResultErrorEnum._(String name) : super(name);

  static BuiltSet<PushResultErrorEnum> get values => _$pushResultErrorEnumValues;
  static PushResultErrorEnum valueOf(String name) => _$pushResultErrorEnumValueOf(name);
}
