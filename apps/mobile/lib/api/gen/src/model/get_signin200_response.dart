//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:wambito/api/gen/src/model/signin_poll.dart';
import 'package:wambito/api/gen/src/model/signin_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/any_of.dart';

part 'get_signin200_response.g.dart';

/// GetSignin200Response
///
/// Properties:
/// * [approverKey] - base64url; null until set
/// * [ready] - The phone sealed the key: pick it up
/// * [expiresAt]
/// * [id]
/// * [commitment] - base64url without padding
/// * [label]
/// * [publicKey] - base64url; null until set
@BuiltValue()
abstract class GetSignin200Response
    implements Built<GetSignin200Response, GetSignin200ResponseBuilder> {
  /// Any Of [SigninPoll], [SigninView]
  AnyOf get anyOf;

  GetSignin200Response._();

  factory GetSignin200Response([void updates(GetSignin200ResponseBuilder b)]) =
      _$GetSignin200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GetSignin200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GetSignin200Response> get serializer => _$GetSignin200ResponseSerializer();
}

class _$GetSignin200ResponseSerializer implements PrimitiveSerializer<GetSignin200Response> {
  @override
  final Iterable<Type> types = const [GetSignin200Response, _$GetSignin200Response];

  @override
  final String wireName = r'GetSignin200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GetSignin200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    GetSignin200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final anyOf = object.anyOf;
    return serializers.serialize(
      anyOf,
      specifiedType: FullType(AnyOf, anyOf.types.map((type) => FullType(type)).toList()),
    )!;
  }

  @override
  GetSignin200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GetSignin200ResponseBuilder();
    Object? anyOfDataSrc;
    final targetType = const FullType(AnyOf, [FullType(SigninPoll), FullType(SigninView)]);
    anyOfDataSrc = serialized;
    result.anyOf = serializers.deserialize(anyOfDataSrc, specifiedType: targetType) as AnyOf;
    return result.build();
  }
}
