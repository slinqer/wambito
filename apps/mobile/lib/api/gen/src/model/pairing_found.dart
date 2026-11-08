//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pairing_found.g.dart';

/// PairingFound
///
/// Properties:
/// * [id]
/// * [publicKey] - base64url without padding
/// * [expiresAt]
@BuiltValue()
abstract class PairingFound implements Built<PairingFound, PairingFoundBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// base64url without padding
  @BuiltValueField(wireName: r'publicKey')
  String get publicKey;

  @BuiltValueField(wireName: r'expiresAt')
  String get expiresAt;

  PairingFound._();

  factory PairingFound([void updates(PairingFoundBuilder b)]) = _$PairingFound;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PairingFoundBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PairingFound> get serializer => _$PairingFoundSerializer();
}

class _$PairingFoundSerializer implements PrimitiveSerializer<PairingFound> {
  @override
  final Iterable<Type> types = const [PairingFound, _$PairingFound];

  @override
  final String wireName = r'PairingFound';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PairingFound object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'publicKey';
    yield serializers.serialize(object.publicKey, specifiedType: const FullType(String));
    yield r'expiresAt';
    yield serializers.serialize(object.expiresAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    PairingFound object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PairingFoundBuilder result,
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
        case r'publicKey':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.publicKey = valueDes;
          break;
        case r'expiresAt':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.expiresAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PairingFound deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PairingFoundBuilder();
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
