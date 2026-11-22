//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_source_recurrences_inner.g.dart';

/// MigrationSourceRecurrencesInner
///
/// Properties:
/// * [id]
/// * [accountId]
/// * [categoryId]
/// * [name]
/// * [amount]
/// * [frequency]
/// * [dayOfMonth]
/// * [monthOfYear]
/// * [startDate] - `YYYY-MM-DD`
/// * [endDate] - `YYYY-MM-DD`
/// * [createdAt] - ISO 8601 timestamp
/// * [updatedAt] - ISO 8601 timestamp
@BuiltValue()
abstract class MigrationSourceRecurrencesInner
    implements Built<MigrationSourceRecurrencesInner, MigrationSourceRecurrencesInnerBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'accountId')
  String get accountId;

  @BuiltValueField(wireName: r'categoryId')
  String get categoryId;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'amount')
  int get amount;

  @BuiltValueField(wireName: r'frequency')
  MigrationSourceRecurrencesInnerFrequencyEnum get frequency;
  // enum frequencyEnum {  monthly,  yearly,  };

  @BuiltValueField(wireName: r'dayOfMonth')
  int get dayOfMonth;

  @BuiltValueField(wireName: r'monthOfYear')
  int? get monthOfYear;

  /// `YYYY-MM-DD`
  @BuiltValueField(wireName: r'startDate')
  String get startDate;

  /// `YYYY-MM-DD`
  @BuiltValueField(wireName: r'endDate')
  String? get endDate;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'createdAt')
  String get createdAt;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'updatedAt')
  String get updatedAt;

  MigrationSourceRecurrencesInner._();

  factory MigrationSourceRecurrencesInner([
    void updates(MigrationSourceRecurrencesInnerBuilder b),
  ]) = _$MigrationSourceRecurrencesInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationSourceRecurrencesInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationSourceRecurrencesInner> get serializer =>
      _$MigrationSourceRecurrencesInnerSerializer();
}

class _$MigrationSourceRecurrencesInnerSerializer
    implements PrimitiveSerializer<MigrationSourceRecurrencesInner> {
  @override
  final Iterable<Type> types = const [
    MigrationSourceRecurrencesInner,
    _$MigrationSourceRecurrencesInner,
  ];

  @override
  final String wireName = r'MigrationSourceRecurrencesInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationSourceRecurrencesInner object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'accountId';
    yield serializers.serialize(object.accountId, specifiedType: const FullType(String));
    yield r'categoryId';
    yield serializers.serialize(object.categoryId, specifiedType: const FullType(String));
    yield r'name';
    yield serializers.serialize(object.name, specifiedType: const FullType(String));
    yield r'amount';
    yield serializers.serialize(object.amount, specifiedType: const FullType(int));
    yield r'frequency';
    yield serializers.serialize(
      object.frequency,
      specifiedType: const FullType(MigrationSourceRecurrencesInnerFrequencyEnum),
    );
    yield r'dayOfMonth';
    yield serializers.serialize(object.dayOfMonth, specifiedType: const FullType(int));
    yield r'monthOfYear';
    yield object.monthOfYear == null
        ? null
        : serializers.serialize(object.monthOfYear, specifiedType: const FullType.nullable(int));
    yield r'startDate';
    yield serializers.serialize(object.startDate, specifiedType: const FullType(String));
    yield r'endDate';
    yield object.endDate == null
        ? null
        : serializers.serialize(object.endDate, specifiedType: const FullType.nullable(String));
    yield r'createdAt';
    yield serializers.serialize(object.createdAt, specifiedType: const FullType(String));
    yield r'updatedAt';
    yield serializers.serialize(object.updatedAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceRecurrencesInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationSourceRecurrencesInnerBuilder result,
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
        case r'accountId':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.accountId = valueDes;
          break;
        case r'categoryId':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.categoryId = valueDes;
          break;
        case r'name':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.name = valueDes;
          break;
        case r'amount':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.amount = valueDes;
          break;
        case r'frequency':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationSourceRecurrencesInnerFrequencyEnum),
          ) as MigrationSourceRecurrencesInnerFrequencyEnum;
          result.frequency = valueDes;
          break;
        case r'dayOfMonth':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.dayOfMonth = valueDes;
          break;
        case r'monthOfYear':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType.nullable(int)) as int?;
          if (valueDes == null) continue;
          result.monthOfYear = valueDes;
          break;
        case r'startDate':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.startDate = valueDes;
          break;
        case r'endDate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.endDate = valueDes;
          break;
        case r'createdAt':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.createdAt = valueDes;
          break;
        case r'updatedAt':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationSourceRecurrencesInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationSourceRecurrencesInnerBuilder();
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

class MigrationSourceRecurrencesInnerFrequencyEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'monthly')
  static const MigrationSourceRecurrencesInnerFrequencyEnum monthly =
      _$migrationSourceRecurrencesInnerFrequencyEnum_monthly;
  @BuiltValueEnumConst(wireName: r'yearly')
  static const MigrationSourceRecurrencesInnerFrequencyEnum yearly =
      _$migrationSourceRecurrencesInnerFrequencyEnum_yearly;

  static Serializer<MigrationSourceRecurrencesInnerFrequencyEnum> get serializer =>
      _$migrationSourceRecurrencesInnerFrequencyEnumSerializer;

  const MigrationSourceRecurrencesInnerFrequencyEnum._(String name) : super(name);

  static BuiltSet<MigrationSourceRecurrencesInnerFrequencyEnum> get values =>
      _$migrationSourceRecurrencesInnerFrequencyEnumValues;
  static MigrationSourceRecurrencesInnerFrequencyEnum valueOf(String name) =>
      _$migrationSourceRecurrencesInnerFrequencyEnumValueOf(name);
}
