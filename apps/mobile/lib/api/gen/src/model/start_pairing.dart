//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'start_pairing.g.dart';

/// StartPairing
///
/// Properties:
/// * [commitment] - SHA-256(\"wambito/v1/pairing-commit\" || the new device's X25519 public key), 32 bytes, base64url
@BuiltValue()
abstract class StartPairing implements Built<StartPairing, StartPairingBuilder> {
  /// SHA-256(\"wambito/v1/pairing-commit\" || the new device's X25519 public key), 32 bytes, base64url
  @BuiltValueField(wireName: r'commitment')
  String get commitment;

  StartPairing._();

  factory StartPairing([void updates(StartPairingBuilder b)]) = _$StartPairing;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StartPairingBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StartPairing> get serializer => _$StartPairingSerializer();
}

class _$StartPairingSerializer implements PrimitiveSerializer<StartPairing> {
  @override
  final Iterable<Type> types = const [StartPairing, _$StartPairing];

  @override
  final String wireName = r'StartPairing';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StartPairing object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'commitment';
    yield serializers.serialize(object.commitment, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    StartPairing object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StartPairingBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'commitment':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.commitment = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  StartPairing deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StartPairingBuilder();
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
