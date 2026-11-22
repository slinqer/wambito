//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_capture.g.dart';

/// CreateCapture
///
/// Properties:
/// * [kind]
/// * [amount]
/// * [currency]
/// * [merchant]
/// * [capturedAt]
/// * [source_]
@BuiltValue()
abstract class CreateCapture implements Built<CreateCapture, CreateCaptureBuilder> {
  @BuiltValueField(wireName: r'kind')
  CreateCaptureKindEnum get kind;
  // enum kindEnum {  expense,  income,  };

  @BuiltValueField(wireName: r'amount')
  int get amount;

  @BuiltValueField(wireName: r'currency')
  String get currency;

  @BuiltValueField(wireName: r'merchant')
  String get merchant;

  @BuiltValueField(wireName: r'capturedAt')
  DateTime get capturedAt;

  @BuiltValueField(wireName: r'source')
  CreateCaptureSource_Enum get source_;
  // enum source_Enum {  revolut,  google_wallet,  apple_wallet,  };

  CreateCapture._();

  factory CreateCapture([void updates(CreateCaptureBuilder b)]) = _$CreateCapture;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateCaptureBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateCapture> get serializer => _$CreateCaptureSerializer();
}

class _$CreateCaptureSerializer implements PrimitiveSerializer<CreateCapture> {
  @override
  final Iterable<Type> types = const [CreateCapture, _$CreateCapture];

  @override
  final String wireName = r'CreateCapture';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateCapture object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(object.kind, specifiedType: const FullType(CreateCaptureKindEnum));
    yield r'amount';
    yield serializers.serialize(object.amount, specifiedType: const FullType(int));
    yield r'currency';
    yield serializers.serialize(object.currency, specifiedType: const FullType(String));
    yield r'merchant';
    yield serializers.serialize(object.merchant, specifiedType: const FullType(String));
    yield r'capturedAt';
    yield serializers.serialize(object.capturedAt, specifiedType: const FullType(DateTime));
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(CreateCaptureSource_Enum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateCapture object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateCaptureBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CreateCaptureKindEnum),
          ) as CreateCaptureKindEnum;
          result.kind = valueDes;
          break;
        case r'amount':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(int)) as int;
          result.amount = valueDes;
          break;
        case r'currency':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.currency = valueDes;
          break;
        case r'merchant':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(String)) as String;
          result.merchant = valueDes;
          break;
        case r'capturedAt':
          final valueDes =
              serializers.deserialize(value, specifiedType: const FullType(DateTime)) as DateTime;
          result.capturedAt = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CreateCaptureSource_Enum),
          ) as CreateCaptureSource_Enum;
          result.source_ = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateCapture deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateCaptureBuilder();
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

class CreateCaptureKindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'expense')
  static const CreateCaptureKindEnum expense = _$createCaptureKindEnum_expense;
  @BuiltValueEnumConst(wireName: r'income')
  static const CreateCaptureKindEnum income = _$createCaptureKindEnum_income;

  static Serializer<CreateCaptureKindEnum> get serializer => _$createCaptureKindEnumSerializer;

  const CreateCaptureKindEnum._(String name) : super(name);

  static BuiltSet<CreateCaptureKindEnum> get values => _$createCaptureKindEnumValues;
  static CreateCaptureKindEnum valueOf(String name) => _$createCaptureKindEnumValueOf(name);
}

class CreateCaptureSource_Enum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'revolut')
  static const CreateCaptureSource_Enum revolut = _$createCaptureSourceEnum_revolut;
  @BuiltValueEnumConst(wireName: r'google_wallet')
  static const CreateCaptureSource_Enum googleWallet = _$createCaptureSourceEnum_googleWallet;
  @BuiltValueEnumConst(wireName: r'apple_wallet')
  static const CreateCaptureSource_Enum appleWallet = _$createCaptureSourceEnum_appleWallet;

  static Serializer<CreateCaptureSource_Enum> get serializer => _$createCaptureSourceEnumSerializer;

  const CreateCaptureSource_Enum._(String name) : super(name);

  static BuiltSet<CreateCaptureSource_Enum> get values => _$createCaptureSourceEnumValues;
  static CreateCaptureSource_Enum valueOf(String name) => _$createCaptureSourceEnumValueOf(name);
}
