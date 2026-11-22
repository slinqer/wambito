//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'signin_poll.g.dart';

/// SigninPoll
///
/// Properties:
/// * [approverKey] - base64url; null until set
/// * [ready] - The phone sealed the key: pick it up
/// * [expiresAt]
@BuiltValue()
abstract class SigninPoll implements Built<SigninPoll, SigninPollBuilder> {
  /// base64url; null until set
  @BuiltValueField(wireName: r'approverKey')
  String? get approverKey;

  /// The phone sealed the key: pick it up
  @BuiltValueField(wireName: r'ready')
  bool get ready;

  @BuiltValueField(wireName: r'expiresAt')
  String get expiresAt;

  SigninPoll._();

  factory SigninPoll([void updates(SigninPollBuilder b)]) = _$SigninPoll;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SigninPollBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SigninPoll> get serializer => _$SigninPollSerializer();
}

class _$SigninPollSerializer implements PrimitiveSerializer<SigninPoll> {
  @override
  final Iterable<Type> types = const [SigninPoll, _$SigninPoll];

  @override
  final String wireName = r'SigninPoll';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SigninPoll object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'approverKey';
    yield object.approverKey == null
        ? null
        : serializers.serialize(object.approverKey, specifiedType: const FullType.nullable(String));
    yield r'ready';
    yield serializers.serialize(object.ready, specifiedType: const FullType(bool));
    yield r'expiresAt';
    yield serializers.serialize(object.expiresAt, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    SigninPoll object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SigninPollBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'approverKey':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.approverKey = valueDes;
          break;
        case r'ready':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(bool)) as bool;
          result.ready = valueDes;
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
  SigninPoll deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SigninPollBuilder();
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
