//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'transaction_page_totals.g.dart';

/// Only with `totals=true`: every match, not just this page
///
/// Properties:
/// * [count]
/// * [expense] - Cents, positive
/// * [income] - Cents, positive
@BuiltValue()
abstract class TransactionPageTotals
    implements Built<TransactionPageTotals, TransactionPageTotalsBuilder> {
  @BuiltValueField(wireName: r'count')
  int get count;

  /// Cents, positive
  @BuiltValueField(wireName: r'expense')
  int get expense;

  /// Cents, positive
  @BuiltValueField(wireName: r'income')
  int get income;

  TransactionPageTotals._();

  factory TransactionPageTotals([void updates(TransactionPageTotalsBuilder b)]) =
      _$TransactionPageTotals;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(TransactionPageTotalsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<TransactionPageTotals> get serializer => _$TransactionPageTotalsSerializer();
}

class _$TransactionPageTotalsSerializer implements PrimitiveSerializer<TransactionPageTotals> {
  @override
  final Iterable<Type> types = const [TransactionPageTotals, _$TransactionPageTotals];

  @override
  final String wireName = r'TransactionPageTotals';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    TransactionPageTotals object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'count';
    yield serializers.serialize(object.count, specifiedType: const FullType(int));
    yield r'expense';
    yield serializers.serialize(object.expense, specifiedType: const FullType(int));
    yield r'income';
    yield serializers.serialize(object.income, specifiedType: const FullType(int));
  }

  @override
  Object serialize(
    Serializers serializers,
    TransactionPageTotals object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required TransactionPageTotalsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'count':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.count = valueDes;
          break;
        case r'expense':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.expense = valueDes;
          break;
        case r'income':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.income = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  TransactionPageTotals deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = TransactionPageTotalsBuilder();
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
