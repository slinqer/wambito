//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_source_transactions_inner.g.dart';

/// MigrationSourceTransactionsInner
///
/// Properties:
/// * [id]
/// * [accountId]
/// * [categoryId]
/// * [name]
/// * [amount]
/// * [currency]
/// * [date] - `YYYY-MM-DD`
/// * [status]
/// * [note]
/// * [recurrenceId]
/// * [occurrenceMonth] - `YYYY-MM-DD`
/// * [importId]
/// * [source_]
/// * [externalHash]
/// * [needsReview]
/// * [captureSource]
/// * [capturedAt] - ISO 8601 timestamp
/// * [captureMerchantKey]
/// * [deletedAt] - ISO 8601 timestamp
/// * [createdAt] - ISO 8601 timestamp
/// * [updatedAt] - ISO 8601 timestamp
@BuiltValue()
abstract class MigrationSourceTransactionsInner
    implements Built<MigrationSourceTransactionsInner, MigrationSourceTransactionsInnerBuilder> {
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

  @BuiltValueField(wireName: r'currency')
  String get currency;

  /// `YYYY-MM-DD`
  @BuiltValueField(wireName: r'date')
  String get date;

  @BuiltValueField(wireName: r'status')
  MigrationSourceTransactionsInnerStatusEnum get status;
  // enum statusEnum {  paid,  pending,  };

  @BuiltValueField(wireName: r'note')
  String? get note;

  @BuiltValueField(wireName: r'recurrenceId')
  String? get recurrenceId;

  /// `YYYY-MM-DD`
  @BuiltValueField(wireName: r'occurrenceMonth')
  String? get occurrenceMonth;

  @BuiltValueField(wireName: r'importId')
  String? get importId;

  @BuiltValueField(wireName: r'source')
  MigrationSourceTransactionsInnerSource_Enum get source_;
  // enum source_Enum {  app,  web,  widget,  mcp,  import,  recurrence,  capture,  };

  @BuiltValueField(wireName: r'externalHash')
  String? get externalHash;

  @BuiltValueField(wireName: r'needsReview')
  bool get needsReview;

  @BuiltValueField(wireName: r'captureSource')
  String? get captureSource;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'capturedAt')
  String? get capturedAt;

  @BuiltValueField(wireName: r'captureMerchantKey')
  String? get captureMerchantKey;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'deletedAt')
  String? get deletedAt;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'createdAt')
  String get createdAt;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'updatedAt')
  String get updatedAt;

  MigrationSourceTransactionsInner._();

  factory MigrationSourceTransactionsInner([
    void updates(MigrationSourceTransactionsInnerBuilder b),
  ]) = _$MigrationSourceTransactionsInner;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationSourceTransactionsInnerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationSourceTransactionsInner> get serializer =>
      _$MigrationSourceTransactionsInnerSerializer();
}

class _$MigrationSourceTransactionsInnerSerializer
    implements PrimitiveSerializer<MigrationSourceTransactionsInner> {
  @override
  final Iterable<Type> types = const [
    MigrationSourceTransactionsInner,
    _$MigrationSourceTransactionsInner,
  ];

  @override
  final String wireName = r'MigrationSourceTransactionsInner';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationSourceTransactionsInner object, {
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
    yield r'currency';
    yield serializers.serialize(object.currency, specifiedType: const FullType(String));
    yield r'date';
    yield serializers.serialize(object.date, specifiedType: const FullType(String));
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(MigrationSourceTransactionsInnerStatusEnum),
    );
    yield r'note';
    yield object.note == null
        ? null
        : serializers.serialize(object.note, specifiedType: const FullType.nullable(String));
    yield r'recurrenceId';
    yield object.recurrenceId == null
        ? null
        : serializers.serialize(
            object.recurrenceId,
            specifiedType: const FullType.nullable(String),
          );
    yield r'occurrenceMonth';
    yield object.occurrenceMonth == null
        ? null
        : serializers.serialize(
            object.occurrenceMonth,
            specifiedType: const FullType.nullable(String),
          );
    yield r'importId';
    yield object.importId == null
        ? null
        : serializers.serialize(object.importId, specifiedType: const FullType.nullable(String));
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(MigrationSourceTransactionsInnerSource_Enum),
    );
    yield r'externalHash';
    yield object.externalHash == null
        ? null
        : serializers.serialize(
            object.externalHash,
            specifiedType: const FullType.nullable(String),
          );
    yield r'needsReview';
    yield serializers.serialize(object.needsReview, specifiedType: const FullType(bool));
    yield r'captureSource';
    yield object.captureSource == null
        ? null
        : serializers.serialize(
            object.captureSource,
            specifiedType: const FullType.nullable(String),
          );
    yield r'capturedAt';
    yield object.capturedAt == null
        ? null
        : serializers.serialize(object.capturedAt, specifiedType: const FullType.nullable(String));
    yield r'captureMerchantKey';
    yield object.captureMerchantKey == null
        ? null
        : serializers.serialize(
            object.captureMerchantKey,
            specifiedType: const FullType.nullable(String),
          );
    yield r'deletedAt';
    yield object.deletedAt == null
        ? null
        : serializers.serialize(object.deletedAt, specifiedType: const FullType.nullable(String));
    yield r'createdAt';
    yield serializers.serialize(object.createdAt, specifiedType: const FullType(String));
    yield r'updatedAt';
    yield serializers.serialize(object.updatedAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceTransactionsInner object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationSourceTransactionsInnerBuilder result,
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
        case r'currency':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.currency = valueDes;
          break;
        case r'date':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.date = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationSourceTransactionsInnerStatusEnum),
          ) as MigrationSourceTransactionsInnerStatusEnum;
          result.status = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.note = valueDes;
          break;
        case r'recurrenceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.recurrenceId = valueDes;
          break;
        case r'occurrenceMonth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.occurrenceMonth = valueDes;
          break;
        case r'importId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.importId = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationSourceTransactionsInnerSource_Enum),
          ) as MigrationSourceTransactionsInnerSource_Enum;
          result.source_ = valueDes;
          break;
        case r'externalHash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.externalHash = valueDes;
          break;
        case r'needsReview':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(bool)) as bool;
          result.needsReview = valueDes;
          break;
        case r'captureSource':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.captureSource = valueDes;
          break;
        case r'capturedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.capturedAt = valueDes;
          break;
        case r'captureMerchantKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.captureMerchantKey = valueDes;
          break;
        case r'deletedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.deletedAt = valueDes;
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
  MigrationSourceTransactionsInner deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationSourceTransactionsInnerBuilder();
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

class MigrationSourceTransactionsInnerStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'paid')
  static const MigrationSourceTransactionsInnerStatusEnum paid =
      _$migrationSourceTransactionsInnerStatusEnum_paid;
  @BuiltValueEnumConst(wireName: r'pending')
  static const MigrationSourceTransactionsInnerStatusEnum pending =
      _$migrationSourceTransactionsInnerStatusEnum_pending;

  static Serializer<MigrationSourceTransactionsInnerStatusEnum> get serializer =>
      _$migrationSourceTransactionsInnerStatusEnumSerializer;

  const MigrationSourceTransactionsInnerStatusEnum._(String name) : super(name);

  static BuiltSet<MigrationSourceTransactionsInnerStatusEnum> get values =>
      _$migrationSourceTransactionsInnerStatusEnumValues;
  static MigrationSourceTransactionsInnerStatusEnum valueOf(String name) =>
      _$migrationSourceTransactionsInnerStatusEnumValueOf(name);
}

class MigrationSourceTransactionsInnerSource_Enum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'app')
  static const MigrationSourceTransactionsInnerSource_Enum app =
      _$migrationSourceTransactionsInnerSourceEnum_app;
  @BuiltValueEnumConst(wireName: r'web')
  static const MigrationSourceTransactionsInnerSource_Enum web =
      _$migrationSourceTransactionsInnerSourceEnum_web;
  @BuiltValueEnumConst(wireName: r'widget')
  static const MigrationSourceTransactionsInnerSource_Enum widget =
      _$migrationSourceTransactionsInnerSourceEnum_widget;
  @BuiltValueEnumConst(wireName: r'mcp')
  static const MigrationSourceTransactionsInnerSource_Enum mcp =
      _$migrationSourceTransactionsInnerSourceEnum_mcp;
  @BuiltValueEnumConst(wireName: r'import')
  static const MigrationSourceTransactionsInnerSource_Enum import_ =
      _$migrationSourceTransactionsInnerSourceEnum_import_;
  @BuiltValueEnumConst(wireName: r'recurrence')
  static const MigrationSourceTransactionsInnerSource_Enum recurrence =
      _$migrationSourceTransactionsInnerSourceEnum_recurrence;
  @BuiltValueEnumConst(wireName: r'capture')
  static const MigrationSourceTransactionsInnerSource_Enum capture =
      _$migrationSourceTransactionsInnerSourceEnum_capture;

  static Serializer<MigrationSourceTransactionsInnerSource_Enum> get serializer =>
      _$migrationSourceTransactionsInnerSourceEnumSerializer;

  const MigrationSourceTransactionsInnerSource_Enum._(String name) : super(name);

  static BuiltSet<MigrationSourceTransactionsInnerSource_Enum> get values =>
      _$migrationSourceTransactionsInnerSourceEnumValues;
  static MigrationSourceTransactionsInnerSource_Enum valueOf(String name) =>
      _$migrationSourceTransactionsInnerSourceEnumValueOf(name);
}
