//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/transaction_page_totals.dart';
import 'package:wambito/api/gen/src/model/transaction.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'transaction_page.g.dart';

/// TransactionPage
///
/// Properties:
/// * [items]
/// * [nextCursor]
/// * [totals]
@BuiltValue()
abstract class TransactionPage implements Built<TransactionPage, TransactionPageBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<Transaction> get items;

  @BuiltValueField(wireName: r'nextCursor')
  String? get nextCursor;

  @BuiltValueField(wireName: r'totals')
  TransactionPageTotals? get totals;

  TransactionPage._();

  factory TransactionPage([void updates(TransactionPageBuilder b)]) = _$TransactionPage;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TransactionPageBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TransactionPage> get serializer => _$TransactionPageSerializer();
}

class _$TransactionPageSerializer implements PrimitiveSerializer<TransactionPage> {
  @override
  final Iterable<Type> types = const [TransactionPage, _$TransactionPage];

  @override
  final String wireName = r'TransactionPage';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TransactionPage object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(Transaction)]),
    );
    yield r'nextCursor';
    yield object.nextCursor == null
        ? null
        : serializers.serialize(object.nextCursor, specifiedType: const FullType.nullable(String));
    if (object.totals != null) {
      yield r'totals';
      yield serializers.serialize(
        object.totals,
        specifiedType: const FullType(TransactionPageTotals),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    TransactionPage object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TransactionPageBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Transaction)]),
          ) as BuiltList<Transaction>;
          result.items.replace(valueDes);
          break;
        case r'nextCursor':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.nextCursor = valueDes;
          break;
        case r'totals':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(TransactionPageTotals),
          ) as TransactionPageTotals?;
          if (valueDes == null) continue;
          result.totals.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TransactionPage deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TransactionPageBuilder();
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
