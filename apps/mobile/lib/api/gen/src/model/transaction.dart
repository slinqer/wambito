//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'transaction.g.dart';

/// Transaction
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
abstract class Transaction implements Built<Transaction, TransactionBuilder> {
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
  TransactionStatusEnum get status;
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
  TransactionSource_Enum get source_;
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

  Transaction._();

  factory Transaction([void updates(TransactionBuilder b)]) = _$Transaction;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TransactionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Transaction> get serializer => _$TransactionSerializer();
}

class _$TransactionSerializer implements PrimitiveSerializer<Transaction> {
  @override
  final Iterable<Type> types = const [Transaction, _$Transaction];

  @override
  final String wireName = r'Transaction';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Transaction object, {
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
      specifiedType: const FullType(TransactionStatusEnum),
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
      specifiedType: const FullType(TransactionSource_Enum),
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
    Transaction object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TransactionBuilder result,
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
            specifiedType: const FullType(TransactionStatusEnum),
          ) as TransactionStatusEnum;
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
            specifiedType: const FullType(TransactionSource_Enum),
          ) as TransactionSource_Enum;
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
  Transaction deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TransactionBuilder();
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

class TransactionStatusEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'paid')
  static const TransactionStatusEnum paid = _$transactionStatusEnum_paid;
  @BuiltValueEnumConst(wireName: r'pending')
  static const TransactionStatusEnum pending = _$transactionStatusEnum_pending;

  static Serializer<TransactionStatusEnum> get serializer => _$transactionStatusEnumSerializer;

  const TransactionStatusEnum._(String name) : super(name);

  static BuiltSet<TransactionStatusEnum> get values => _$transactionStatusEnumValues;
  static TransactionStatusEnum valueOf(String name) => _$transactionStatusEnumValueOf(name);
}

class TransactionSource_Enum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'app')
  static const TransactionSource_Enum app = _$transactionSourceEnum_app;
  @BuiltValueEnumConst(wireName: r'web')
  static const TransactionSource_Enum web = _$transactionSourceEnum_web;
  @BuiltValueEnumConst(wireName: r'widget')
  static const TransactionSource_Enum widget = _$transactionSourceEnum_widget;
  @BuiltValueEnumConst(wireName: r'mcp')
  static const TransactionSource_Enum mcp = _$transactionSourceEnum_mcp;
  @BuiltValueEnumConst(wireName: r'import')
  static const TransactionSource_Enum import_ = _$transactionSourceEnum_import_;
  @BuiltValueEnumConst(wireName: r'recurrence')
  static const TransactionSource_Enum recurrence = _$transactionSourceEnum_recurrence;
  @BuiltValueEnumConst(wireName: r'capture')
  static const TransactionSource_Enum capture = _$transactionSourceEnum_capture;

  static Serializer<TransactionSource_Enum> get serializer => _$transactionSourceEnumSerializer;

  const TransactionSource_Enum._(String name) : super(name);

  static BuiltSet<TransactionSource_Enum> get values => _$transactionSourceEnumValues;
  static TransactionSource_Enum valueOf(String name) => _$transactionSourceEnumValueOf(name);
}
