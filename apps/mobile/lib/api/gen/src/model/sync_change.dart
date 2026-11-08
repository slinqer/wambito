//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'sync_change.g.dart';

/// SyncChange
///
/// Properties:
/// * [id]
/// * [type]
/// * [deleted]
/// * [keyV] - The data key version of `body`
/// * [encV] - The record format version
/// * [baseVersion] - The version this change was made on; null creates the record
/// * [body] - The encrypted record, base64url without padding, at most 65536 bytes decoded; null exactly when deleted
@BuiltValue()
abstract class SyncChange implements Built<SyncChange, SyncChangeBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'type')
  SyncChangeTypeEnum get type;
  // enum typeEnum {  transaction,  category,  budget,  recurrence,  merchant,  settings,  account,  };

  @BuiltValueField(wireName: r'deleted')
  bool get deleted;

  /// The data key version of `body`
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  /// The record format version
  @BuiltValueField(wireName: r'encV')
  int get encV;

  /// The version this change was made on; null creates the record
  @BuiltValueField(wireName: r'baseVersion')
  int? get baseVersion;

  /// The encrypted record, base64url without padding, at most 65536 bytes decoded; null exactly when deleted
  @BuiltValueField(wireName: r'body')
  String? get body;

  SyncChange._();

  factory SyncChange([void updates(SyncChangeBuilder b)]) = _$SyncChange;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SyncChangeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SyncChange> get serializer => _$SyncChangeSerializer();
}

class _$SyncChangeSerializer implements PrimitiveSerializer<SyncChange> {
  @override
  final Iterable<Type> types = const [SyncChange, _$SyncChange];

  @override
  final String wireName = r'SyncChange';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SyncChange object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'type';
    yield serializers.serialize(object.type, specifiedType: const FullType(SyncChangeTypeEnum));
    yield r'deleted';
    yield serializers.serialize(object.deleted, specifiedType: const FullType(bool));
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
    yield r'encV';
    yield serializers.serialize(object.encV, specifiedType: const FullType(int));
    yield r'baseVersion';
    yield object.baseVersion == null
        ? null
        : serializers.serialize(object.baseVersion, specifiedType: const FullType.nullable(int));
    yield r'body';
    yield object.body == null
        ? null
        : serializers.serialize(object.body, specifiedType: const FullType.nullable(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    SyncChange object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SyncChangeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.id = valueDes;
          break;
        case r'type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SyncChangeTypeEnum),
          ) as SyncChangeTypeEnum;
          result.type = valueDes;
          break;
        case r'deleted':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(bool)) as bool;
          result.deleted = valueDes;
          break;
        case r'keyV':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.keyV = valueDes;
          break;
        case r'encV':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.encV = valueDes;
          break;
        case r'baseVersion':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType.nullable(int)) as int?;
          if (valueDes == null) continue;
          result.baseVersion = valueDes;
          break;
        case r'body':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.body = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SyncChange deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SyncChangeBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

class SyncChangeTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'transaction')
  static const SyncChangeTypeEnum transaction = _$syncChangeTypeEnum_transaction;
  @BuiltValueEnumConst(wireName: r'category')
  static const SyncChangeTypeEnum category = _$syncChangeTypeEnum_category;
  @BuiltValueEnumConst(wireName: r'budget')
  static const SyncChangeTypeEnum budget = _$syncChangeTypeEnum_budget;
  @BuiltValueEnumConst(wireName: r'recurrence')
  static const SyncChangeTypeEnum recurrence = _$syncChangeTypeEnum_recurrence;
  @BuiltValueEnumConst(wireName: r'merchant')
  static const SyncChangeTypeEnum merchant = _$syncChangeTypeEnum_merchant;
  @BuiltValueEnumConst(wireName: r'settings')
  static const SyncChangeTypeEnum settings = _$syncChangeTypeEnum_settings;
  @BuiltValueEnumConst(wireName: r'account')
  static const SyncChangeTypeEnum account = _$syncChangeTypeEnum_account;

  static Serializer<SyncChangeTypeEnum> get serializer => _$syncChangeTypeEnumSerializer;

  const SyncChangeTypeEnum._(String name) : super(name);

  static BuiltSet<SyncChangeTypeEnum> get values => _$syncChangeTypeEnumValues;
  static SyncChangeTypeEnum valueOf(String name) => _$syncChangeTypeEnumValueOf(name);
}
