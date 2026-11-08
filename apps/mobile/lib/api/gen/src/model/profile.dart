//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'profile.g.dart';

/// Profile
///
/// Properties:
/// * [id]
/// * [email]
/// * [timezone]
/// * [locale]
/// * [onboardingCompletedAt]
/// * [currency]
/// * [isAnonymous]
/// * [encryption]
@BuiltValue()
abstract class Profile implements Built<Profile, ProfileBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'email')
  String get email;

  @BuiltValueField(wireName: r'timezone')
  String get timezone;

  @BuiltValueField(wireName: r'locale')
  String get locale;

  @BuiltValueField(wireName: r'onboardingCompletedAt')
  String? get onboardingCompletedAt;

  @BuiltValueField(wireName: r'currency')
  String get currency;

  @BuiltValueField(wireName: r'isAnonymous')
  bool get isAnonymous;

  @BuiltValueField(wireName: r'encryption')
  ProfileEncryptionEnum get encryption;
  // enum encryptionEnum {  plain,  preview,  };

  Profile._();

  factory Profile([void updates(ProfileBuilder b)]) = _$Profile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Profile> get serializer => _$ProfileSerializer();
}

class _$ProfileSerializer implements PrimitiveSerializer<Profile> {
  @override
  final Iterable<Type> types = const [Profile, _$Profile];

  @override
  final String wireName = r'Profile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Profile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'email';
    yield serializers.serialize(object.email, specifiedType: const FullType(String));
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
    yield r'isAnonymous';
    yield serializers.serialize(object.isAnonymous, specifiedType: const FullType(bool));
    yield r'encryption';
    yield serializers.serialize(
      object.encryption,
      specifiedType: const FullType(ProfileEncryptionEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Profile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ProfileBuilder result,
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
        case r'email':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.email = valueDes;
          break;
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
        case r'isAnonymous':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(bool)) as bool;
          result.isAnonymous = valueDes;
          break;
        case r'encryption':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ProfileEncryptionEnum),
          ) as ProfileEncryptionEnum;
          result.encryption = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Profile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ProfileBuilder();
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

class ProfileEncryptionEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'plain')
  static const ProfileEncryptionEnum plain = _$profileEncryptionEnum_plain;
  @BuiltValueEnumConst(wireName: r'preview')
  static const ProfileEncryptionEnum preview = _$profileEncryptionEnum_preview;

  static Serializer<ProfileEncryptionEnum> get serializer => _$profileEncryptionEnumSerializer;

  const ProfileEncryptionEnum._(String name) : super(name);

  static BuiltSet<ProfileEncryptionEnum> get values => _$profileEncryptionEnumValues;
  static ProfileEncryptionEnum valueOf(String name) => _$profileEncryptionEnumValueOf(name);
}
