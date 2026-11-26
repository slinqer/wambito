//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'capture_result_transaction.g.dart';

/// CaptureResultTransaction
///
/// Properties:
/// * [id]
/// * [name]
/// * [amount]
/// * [currency]
/// * [date]
/// * [status]
/// * [note]
/// * [categoryId]
/// * [recurrenceId]
/// * [importId]
/// * [source_]
/// * [needsReview]
/// * [captureSource] - Where a detected transaction came from: revolut, google_wallet, apple_wallet, activobank, or a newer source
/// * [createdAt]
/// * [updatedAt]
@BuiltValue()
abstract class CaptureResultTransaction
    implements Built<CaptureResultTransaction, CaptureResultTransactionBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'amount')
  int get amount;

  @BuiltValueField(wireName: r'currency')
  String get currency;

  @BuiltValueField(wireName: r'date')
  String get date;

  @BuiltValueField(wireName: r'status')
  CaptureResultTransactionStatusEnum get status;
  // enum statusEnum {  paid,  pending,  };

  @BuiltValueField(wireName: r'note')
  String? get note;

  @BuiltValueField(wireName: r'categoryId')
  String get categoryId;

  @BuiltValueField(wireName: r'recurrenceId')
  String? get recurrenceId;

  @BuiltValueField(wireName: r'importId')
  String? get importId;

  @BuiltValueField(wireName: r'source')
  CaptureResultTransactionSource_Enum get source_;
  // enum source_Enum {  app,  web,  widget,  mcp,  import,  recurrence,  capture,  };

  @BuiltValueField(wireName: r'needsReview')
  bool get needsReview;

  /// Where a detected transaction came from: revolut, google_wallet, apple_wallet, activobank, or a newer source
  @BuiltValueField(wireName: r'captureSource')
  String? get captureSource;

  @BuiltValueField(wireName: r'createdAt')
  String get createdAt;

  @BuiltValueField(wireName: r'updatedAt')
  String get updatedAt;

  CaptureResultTransaction._();

  factory CaptureResultTransaction([void updates(CaptureResultTransactionBuilder b)]) =
      _$CaptureResultTransaction;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CaptureResultTransactionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CaptureResultTransaction> get serializer =>
      _$CaptureResultTransactionSerializer();
}

class _$CaptureResultTransactionSerializer
    implements PrimitiveSerializer<CaptureResultTransaction> {
  @override
  final Iterable<Type> types = const [CaptureResultTransaction, _$CaptureResultTransaction];

  @override
  final String wireName = r'CaptureResultTransaction';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CaptureResultTransaction object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
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
      specifiedType: const FullType(CaptureResultTransactionStatusEnum),
    );
    yield r'note';
    yield object.note == null
        ? null
        : serializers.serialize(object.note, specifiedType: const FullType.nullable(String));
    yield r'categoryId';
    yield serializers.serialize(object.categoryId, specifiedType: const FullType(String));
    yield r'recurrenceId';
    yield object.recurrenceId == null
        ? null
        : serializers.serialize(
            object.recurrenceId,
            specifiedType: const FullType.nullable(String),
          );
    yield r'importId';
    yield object.importId == null
        ? null
        : serializers.serialize(object.importId, specifiedType: const FullType.nullable(String));
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(CaptureResultTransactionSource_Enum),
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
    yield r'createdAt';
    yield serializers.serialize(object.createdAt, specifiedType: const FullType(String));
    yield r'updatedAt';
    yield serializers.serialize(object.updatedAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    CaptureResultTransaction object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CaptureResultTransactionBuilder result,
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
            specifiedType: const FullType(CaptureResultTransactionStatusEnum),
          ) as CaptureResultTransactionStatusEnum;
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
        case r'categoryId':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.categoryId = valueDes;
          break;
        case r'recurrenceId':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.recurrenceId = valueDes;
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
            specifiedType: const FullType(CaptureResultTransactionSource_Enum),
          ) as CaptureResultTransactionSource_Enum;
          result.source_ = valueDes;
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
  CaptureResultTransaction deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CaptureResultTransactionBuilder();
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

class CaptureResultTransactionStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'paid')
  static const CaptureResultTransactionStatusEnum paid = _$captureResultTransactionStatusEnum_paid;
  @BuiltValueEnumConst(wireName: r'pending')
  static const CaptureResultTransactionStatusEnum pending =
      _$captureResultTransactionStatusEnum_pending;

  static Serializer<CaptureResultTransactionStatusEnum> get serializer =>
      _$captureResultTransactionStatusEnumSerializer;

  const CaptureResultTransactionStatusEnum._(String name) : super(name);

  static BuiltSet<CaptureResultTransactionStatusEnum> get values =>
      _$captureResultTransactionStatusEnumValues;
  static CaptureResultTransactionStatusEnum valueOf(String name) =>
      _$captureResultTransactionStatusEnumValueOf(name);
}

class CaptureResultTransactionSource_Enum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'app')
  static const CaptureResultTransactionSource_Enum app = _$captureResultTransactionSourceEnum_app;
  @BuiltValueEnumConst(wireName: r'web')
  static const CaptureResultTransactionSource_Enum web = _$captureResultTransactionSourceEnum_web;
  @BuiltValueEnumConst(wireName: r'widget')
  static const CaptureResultTransactionSource_Enum widget =
      _$captureResultTransactionSourceEnum_widget;
  @BuiltValueEnumConst(wireName: r'mcp')
  static const CaptureResultTransactionSource_Enum mcp = _$captureResultTransactionSourceEnum_mcp;
  @BuiltValueEnumConst(wireName: r'import')
  static const CaptureResultTransactionSource_Enum import_ =
      _$captureResultTransactionSourceEnum_import_;
  @BuiltValueEnumConst(wireName: r'recurrence')
  static const CaptureResultTransactionSource_Enum recurrence =
      _$captureResultTransactionSourceEnum_recurrence;
  @BuiltValueEnumConst(wireName: r'capture')
  static const CaptureResultTransactionSource_Enum capture =
      _$captureResultTransactionSourceEnum_capture;

  static Serializer<CaptureResultTransactionSource_Enum> get serializer =>
      _$captureResultTransactionSourceEnumSerializer;

  const CaptureResultTransactionSource_Enum._(String name) : super(name);

  static BuiltSet<CaptureResultTransactionSource_Enum> get values =>
      _$captureResultTransactionSourceEnumValues;
  static CaptureResultTransactionSource_Enum valueOf(String name) =>
      _$captureResultTransactionSourceEnumValueOf(name);
}
