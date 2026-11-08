//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pairing_approver.g.dart';

/// PairingApprover
///
/// Properties:
/// * [publicKey] - The approving device's ephemeral X25519 public key, 32 bytes, base64url
@BuiltValue()
abstract class PairingApprover implements Built<PairingApprover, PairingApproverBuilder> {
  /// The approving device's ephemeral X25519 public key, 32 bytes, base64url
  @BuiltValueField(wireName: r'publicKey')
  String get publicKey;

  PairingApprover._();

  factory PairingApprover([void updates(PairingApproverBuilder b)]) = _$PairingApprover;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PairingApproverBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PairingApprover> get serializer => _$PairingApproverSerializer();
}

class _$PairingApproverSerializer implements PrimitiveSerializer<PairingApprover> {
  @override
  final Iterable<Type> types = const [PairingApprover, _$PairingApprover];

  @override
  final String wireName = r'PairingApprover';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PairingApprover object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'publicKey';
    yield serializers.serialize(object.publicKey, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    PairingApprover object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PairingApproverBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'publicKey':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.publicKey = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PairingApprover deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PairingApproverBuilder();
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
