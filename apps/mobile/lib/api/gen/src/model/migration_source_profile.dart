//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'migration_source_profile.g.dart';

/// MigrationSourceProfile
///
/// Properties:
/// * [timezone]
/// * [locale]
/// * [onboardingCompletedAt] - ISO 8601 timestamp
/// * [currency] - The default account's currency
@BuiltValue()
abstract class MigrationSourceProfile
    implements Built<MigrationSourceProfile, MigrationSourceProfileBuilder> {
  @BuiltValueField(wireName: r'timezone')
  String get timezone;

  @BuiltValueField(wireName: r'locale')
  String get locale;

  /// ISO 8601 timestamp
  @BuiltValueField(wireName: r'onboardingCompletedAt')
  String? get onboardingCompletedAt;

  /// The default account's currency
  @BuiltValueField(wireName: r'currency')
  String get currency;

  MigrationSourceProfile._();

  factory MigrationSourceProfile([void updates(MigrationSourceProfileBuilder b)]) =
      _$MigrationSourceProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MigrationSourceProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MigrationSourceProfile> get serializer => _$MigrationSourceProfileSerializer();
}

class _$MigrationSourceProfileSerializer implements PrimitiveSerializer<MigrationSourceProfile> {
  @override
  final Iterable<Type> types = const [MigrationSourceProfile, _$MigrationSourceProfile];

  @override
  final String wireName = r'MigrationSourceProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MigrationSourceProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'timezone';
    yield serializers.serialize(object.timezone, specifiedType: const FullType(String));
    yield r'locale';
    yield serializers.serialize(object.locale, specifiedType: const FullType(String));
    yield r'onboardingCompletedAt';
    yield object.onboardingCompletedAt == null
        ? null
        : serializers.serialize(
            object.onboardingCompletedAt,
            specifiedType: const FullType.nullable(String),
          );
    yield r'currency';
    yield serializers.serialize(object.currency, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MigrationSourceProfileBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'timezone':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.timezone = valueDes;
          break;
        case r'locale':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.locale = valueDes;
          break;
        case r'onboardingCompletedAt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.onboardingCompletedAt = valueDes;
          break;
        case r'currency':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.currency = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MigrationSourceProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MigrationSourceProfileBuilder();
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
