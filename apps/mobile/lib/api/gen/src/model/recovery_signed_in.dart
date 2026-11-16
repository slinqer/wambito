//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'recovery_signed_in.g.dart';

/// RecoverySignedIn
///
/// Properties:
/// * [userId] - The account signed in to
@BuiltValue()
abstract class RecoverySignedIn implements Built<RecoverySignedIn, RecoverySignedInBuilder> {
  /// The account signed in to
  @BuiltValueField(wireName: r'userId')
  String get userId;

  RecoverySignedIn._();

  factory RecoverySignedIn([void updates(RecoverySignedInBuilder b)]) = _$RecoverySignedIn;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RecoverySignedInBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RecoverySignedIn> get serializer => _$RecoverySignedInSerializer();
}

class _$RecoverySignedInSerializer implements PrimitiveSerializer<RecoverySignedIn> {
  @override
  final Iterable<Type> types = const [RecoverySignedIn, _$RecoverySignedIn];

  @override
  final String wireName = r'RecoverySignedIn';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RecoverySignedIn object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'userId';
    yield serializers.serialize(object.userId, specifiedType: const FullType(String));
  }

  @override
  Object serialize(
    Serializers serializers,
    RecoverySignedIn object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RecoverySignedInBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'userId':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.userId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RecoverySignedIn deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RecoverySignedInBuilder();
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
