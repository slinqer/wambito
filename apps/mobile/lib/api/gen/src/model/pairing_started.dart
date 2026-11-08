//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pairing_started.g.dart';

/// PairingStarted
///
/// Properties:
/// * [id]
/// * [code] - 8 Crockford base32 characters for the person to type
/// * [expiresAt]
@BuiltValue()
abstract class PairingStarted implements Built<PairingStarted, PairingStartedBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// 8 Crockford base32 characters for the person to type
  @BuiltValueField(wireName: r'code')
  String get code;

  @BuiltValueField(wireName: r'expiresAt')
  String get expiresAt;

  PairingStarted._();

  factory PairingStarted([void updates(PairingStartedBuilder b)]) = _$PairingStarted;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PairingStartedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PairingStarted> get serializer => _$PairingStartedSerializer();
}

class _$PairingStartedSerializer implements PrimitiveSerializer<PairingStarted> {
  @override
  final Iterable<Type> types = const [PairingStarted, _$PairingStarted];

  @override
  final String wireName = r'PairingStarted';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PairingStarted object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(object.id, specifiedType: const FullType(String));
    yield r'code';
    yield serializers.serialize(object.code, specifiedType: const FullType(String));
    yield r'expiresAt';
    yield serializers.serialize(object.expiresAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    PairingStarted object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PairingStartedBuilder result,
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
        case r'code':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.code = valueDes;
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
  PairingStarted deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PairingStartedBuilder();
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
