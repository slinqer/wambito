//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'put_recovery_verifier.g.dart';

/// PutRecoveryVerifier
///
/// Properties:
/// * [lookupHash] - SHA-256 of the recovery key's lookup bytes, 32 bytes, base64url
/// * [authHash] - SHA-256 of the recovery key's auth bytes, 32 bytes, base64url
@BuiltValue()
abstract class PutRecoveryVerifier
    implements Built<PutRecoveryVerifier, PutRecoveryVerifierBuilder> {
  /// SHA-256 of the recovery key's lookup bytes, 32 bytes, base64url
  @BuiltValueField(wireName: r'lookupHash')
  String get lookupHash;

  /// SHA-256 of the recovery key's auth bytes, 32 bytes, base64url
  @BuiltValueField(wireName: r'authHash')
  String get authHash;

  PutRecoveryVerifier._();

  factory PutRecoveryVerifier([void updates(PutRecoveryVerifierBuilder b)]) = _$PutRecoveryVerifier;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PutRecoveryVerifierBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PutRecoveryVerifier> get serializer => _$PutRecoveryVerifierSerializer();
}

class _$PutRecoveryVerifierSerializer implements PrimitiveSerializer<PutRecoveryVerifier> {
  @override
  final Iterable<Type> types = const [PutRecoveryVerifier, _$PutRecoveryVerifier];

  @override
  final String wireName = r'PutRecoveryVerifier';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PutRecoveryVerifier object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'lookupHash';
    yield serializers.serialize(object.lookupHash, specifiedType: const FullType(String));
    yield r'authHash';
    yield serializers.serialize(object.authHash, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    PutRecoveryVerifier object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PutRecoveryVerifierBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'lookupHash':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.lookupHash = valueDes;
          break;
        case r'authHash':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.authHash = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PutRecoveryVerifier deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PutRecoveryVerifierBuilder();
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
