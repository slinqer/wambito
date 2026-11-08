//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pairing_state.g.dart';

/// PairingState
///
/// Properties:
/// * [commitment] - base64url
/// * [approverKey] - base64url; null until set
/// * [publicKey] - base64url; null until set
/// * [sealed_] - base64url; null until set
/// * [keyV] - null until sealed
/// * [expiresAt]
@BuiltValue()
abstract class PairingState implements Built<PairingState, PairingStateBuilder> {
  /// base64url
  @BuiltValueField(wireName: r'commitment')
  String get commitment;

  /// base64url; null until set
  @BuiltValueField(wireName: r'approverKey')
  String? get approverKey;

  /// base64url; null until set
  @BuiltValueField(wireName: r'publicKey')
  String? get publicKey;

  /// base64url; null until set
  @BuiltValueField(wireName: r'sealed')
  String? get sealed_;

  /// null until sealed
  @BuiltValueField(wireName: r'keyV')
  int? get keyV;

  @BuiltValueField(wireName: r'expiresAt')
  String get expiresAt;

  PairingState._();

  factory PairingState([void updates(PairingStateBuilder b)]) = _$PairingState;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PairingStateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PairingState> get serializer => _$PairingStateSerializer();
}

class _$PairingStateSerializer implements PrimitiveSerializer<PairingState> {
  @override
  final Iterable<Type> types = const [PairingState, _$PairingState];

  @override
  final String wireName = r'PairingState';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PairingState object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'commitment';
    yield serializers.serialize(object.commitment, specifiedType: const FullType(String));
    yield r'approverKey';
    yield object.approverKey == null
        ? null
        : serializers.serialize(object.approverKey, specifiedType: const FullType.nullable(String));
    yield r'publicKey';
    yield object.publicKey == null
        ? null
        : serializers.serialize(object.publicKey, specifiedType: const FullType.nullable(String));
    yield r'sealed';
    yield object.sealed_ == null
        ? null
        : serializers.serialize(object.sealed_, specifiedType: const FullType.nullable(String));
    yield r'keyV';
    yield object.keyV == null
        ? null
        : serializers.serialize(object.keyV, specifiedType: const FullType.nullable(int));
    yield r'expiresAt';
    yield serializers.serialize(object.expiresAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    PairingState object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PairingStateBuilder result,
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
        case r'approverKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.approverKey = valueDes;
          break;
        case r'publicKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.publicKey = valueDes;
          break;
        case r'sealed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.sealed_ = valueDes;
          break;
        case r'keyV':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType.nullable(int)) as int?;
          if (valueDes == null) continue;
          result.keyV = valueDes;
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
  PairingState deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PairingStateBuilder();
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
