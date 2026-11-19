//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/migration_source_recurrences_inner.dart';
import 'package:built_collection/built_collection.dart';
import 'package:wambito/api/gen/src/model/migration_source_merchants_inner.dart';
import 'package:wambito/api/gen/src/model/migration_source_transactions_inner.dart';
import 'package:wambito/api/gen/src/model/migration_source_profile.dart';
import 'package:wambito/api/gen/src/model/migration_source_budgets_inner.dart';
import 'package:wambito/api/gen/src/model/migration_source_categories_inner.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_source.g.dart';

/// MigrationSource
///
/// Properties:
/// * [profile]
/// * [categories]
/// * [budgets]
/// * [recurrences]
/// * [transactions] - Live rows and every soft-deleted one the server still has
/// * [merchants]
@BuiltValue()
abstract class MigrationSource implements Built<MigrationSource, MigrationSourceBuilder> {
  @BuiltValueField(wireName: r'profile')
  MigrationSourceProfile get profile;

  @BuiltValueField(wireName: r'categories')
  BuiltList<MigrationSourceCategoriesInner> get categories;

  @BuiltValueField(wireName: r'budgets')
  BuiltList<MigrationSourceBudgetsInner> get budgets;

  @BuiltValueField(wireName: r'recurrences')
  BuiltList<MigrationSourceRecurrencesInner> get recurrences;

  /// Live rows and every soft-deleted one the server still has
  @BuiltValueField(wireName: r'transactions')
  BuiltList<MigrationSourceTransactionsInner> get transactions;

  @BuiltValueField(wireName: r'merchants')
  BuiltList<MigrationSourceMerchantsInner> get merchants;

  MigrationSource._();

  factory MigrationSource([void updates(MigrationSourceBuilder b)]) = _$MigrationSource;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationSourceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationSource> get serializer => _$MigrationSourceSerializer();
}

class _$MigrationSourceSerializer implements PrimitiveSerializer<MigrationSource> {
  @override
  final Iterable<Type> types = const [MigrationSource, _$MigrationSource];

  @override
  final String wireName = r'MigrationSource';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationSource object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'profile';
    yield serializers.serialize(
      object.profile,
      specifiedType: const FullType(MigrationSourceProfile),
    );
    yield r'categories';
    yield serializers.serialize(
      object.categories,
      specifiedType: const FullType(BuiltList, [FullType(MigrationSourceCategoriesInner)]),
    );
    yield r'budgets';
    yield serializers.serialize(
      object.budgets,
      specifiedType: const FullType(BuiltList, [FullType(MigrationSourceBudgetsInner)]),
    );
    yield r'recurrences';
    yield serializers.serialize(
      object.recurrences,
      specifiedType: const FullType(BuiltList, [FullType(MigrationSourceRecurrencesInner)]),
    );
    yield r'transactions';
    yield serializers.serialize(
      object.transactions,
      specifiedType: const FullType(BuiltList, [FullType(MigrationSourceTransactionsInner)]),
    );
    yield r'merchants';
    yield serializers.serialize(
      object.merchants,
      specifiedType: const FullType(BuiltList, [FullType(MigrationSourceMerchantsInner)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationSource object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationSourceBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'profile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MigrationSourceProfile),
          ) as MigrationSourceProfile;
          result.profile.replace(valueDes);
          break;
        case r'categories':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MigrationSourceCategoriesInner)]),
          ) as BuiltList<MigrationSourceCategoriesInner>;
          result.categories.replace(valueDes);
          break;
        case r'budgets':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MigrationSourceBudgetsInner)]),
          ) as BuiltList<MigrationSourceBudgetsInner>;
          result.budgets.replace(valueDes);
          break;
        case r'recurrences':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MigrationSourceRecurrencesInner)]),
          ) as BuiltList<MigrationSourceRecurrencesInner>;
          result.recurrences.replace(valueDes);
          break;
        case r'transactions':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MigrationSourceTransactionsInner)]),
          ) as BuiltList<MigrationSourceTransactionsInner>;
          result.transactions.replace(valueDes);
          break;
        case r'merchants':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MigrationSourceMerchantsInner)]),
          ) as BuiltList<MigrationSourceMerchantsInner>;
          result.merchants.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationSource deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationSourceBuilder();
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
