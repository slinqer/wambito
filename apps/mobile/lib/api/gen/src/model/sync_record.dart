//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'sync_record.g.dart';

/// SyncRecord
///
/// Properties:
/// * [id] - A UUID in lower case
/// * [type]
/// * [deleted]
/// * [keyV] - The data key version of `body`
/// * [encV] - The record format version
/// * [version]
/// * [body] - The encrypted record, base64url without padding; null when deleted
@BuiltValue()
abstract class SyncRecord implements Built<SyncRecord, SyncRecordBuilder> {
  /// A UUID in lower case
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'type')
  SyncRecordTypeEnum get type;
  // enum typeEnum {  transaction,  category,  budget,  recurrence,  merchant,  settings,  account,  };

  @BuiltValueField(wireName: r'deleted')
  bool get deleted;

  /// The data key version of `body`
  @BuiltValueField(wireName: r'keyV')
  int get keyV;

  /// The record format version
  @BuiltValueField(wireName: r'encV')
  int get encV;

  @BuiltValueField(wireName: r'version')
  int get version;

  /// The encrypted record, base64url without padding; null when deleted
  @BuiltValueField(wireName: r'body')
  String? get body;

  SyncRecord._();

  factory SyncRecord([void updates(SyncRecordBuilder b)]) = _$SyncRecord;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SyncRecordBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SyncRecord> get serializer => _$SyncRecordSerializer();
}

class _$SyncRecordSerializer implements PrimitiveSerializer<SyncRecord> {
  @override
  final Iterable<Type> types = const [SyncRecord, _$SyncRecord];

  @override
  final String wireName = r'SyncRecord';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SyncRecord object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'type';
    yield serializers.serialize(object.type, specifiedType: const FullType(SyncRecordTypeEnum));
    yield r'deleted';
    yield serializers.serialize(object.deleted, specifiedType: const FullType(bool));
    yield r'keyV';
    yield serializers.serialize(object.keyV, specifiedType: const FullType(int));
    yield r'encV';
    yield serializers.serialize(object.encV, specifiedType: const FullType(int));
    yield r'version';
    yield serializers.serialize(object.version, specifiedType: const FullType(int));
    yield r'body';
    yield object.body == null
        ? null
        : serializers.serialize(object.body, specifiedType: const FullType.nullable(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    SyncRecord object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SyncRecordBuilder result,
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
            specifiedType: const FullType(SyncRecordTypeEnum),
          ) as SyncRecordTypeEnum;
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
        case r'version':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.version = valueDes;
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
  SyncRecord deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SyncRecordBuilder();
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

class SyncRecordTypeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'transaction')
  static const SyncRecordTypeEnum transaction = _$syncRecordTypeEnum_transaction;
  @BuiltValueEnumConst(wireName: r'category')
  static const SyncRecordTypeEnum category = _$syncRecordTypeEnum_category;
  @BuiltValueEnumConst(wireName: r'budget')
  static const SyncRecordTypeEnum budget = _$syncRecordTypeEnum_budget;
  @BuiltValueEnumConst(wireName: r'recurrence')
  static const SyncRecordTypeEnum recurrence = _$syncRecordTypeEnum_recurrence;
  @BuiltValueEnumConst(wireName: r'merchant')
  static const SyncRecordTypeEnum merchant = _$syncRecordTypeEnum_merchant;
  @BuiltValueEnumConst(wireName: r'settings')
  static const SyncRecordTypeEnum settings = _$syncRecordTypeEnum_settings;
  @BuiltValueEnumConst(wireName: r'account')
  static const SyncRecordTypeEnum account = _$syncRecordTypeEnum_account;

  static Serializer<SyncRecordTypeEnum> get serializer => _$syncRecordTypeEnumSerializer;

  const SyncRecordTypeEnum._(String name) : super(name);

  static BuiltSet<SyncRecordTypeEnum> get values => _$syncRecordTypeEnumValues;
  static SyncRecordTypeEnum valueOf(String name) => _$syncRecordTypeEnumValueOf(name);
}
