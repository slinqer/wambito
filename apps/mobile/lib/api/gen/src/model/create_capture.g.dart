// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_capture.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CreateCaptureKindEnum _$createCaptureKindEnum_expense = const CreateCaptureKindEnum._(
  'expense',
);
const CreateCaptureKindEnum _$createCaptureKindEnum_income = const CreateCaptureKindEnum._(
  'income',
);

CreateCaptureKindEnum _$createCaptureKindEnumValueOf(String name) {
  switch (name) {
    case 'expense':
      return _$createCaptureKindEnum_expense;
    case 'income':
      return _$createCaptureKindEnum_income;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CreateCaptureKindEnum> _$createCaptureKindEnumValues =
    BuiltSet<CreateCaptureKindEnum>(const <CreateCaptureKindEnum>[
      _$createCaptureKindEnum_expense,
      _$createCaptureKindEnum_income,
    ]);

const CreateCaptureSource_Enum _$createCaptureSourceEnum_revolut = const CreateCaptureSource_Enum._(
  'revolut',
);
const CreateCaptureSource_Enum _$createCaptureSourceEnum_googleWallet =
    const CreateCaptureSource_Enum._('googleWallet');
const CreateCaptureSource_Enum _$createCaptureSourceEnum_appleWallet =
    const CreateCaptureSource_Enum._('appleWallet');
const CreateCaptureSource_Enum _$createCaptureSourceEnum_activobank =
    const CreateCaptureSource_Enum._('activobank');

CreateCaptureSource_Enum _$createCaptureSourceEnumValueOf(String name) {
  switch (name) {
    case 'revolut':
      return _$createCaptureSourceEnum_revolut;
    case 'googleWallet':
      return _$createCaptureSourceEnum_googleWallet;
    case 'appleWallet':
      return _$createCaptureSourceEnum_appleWallet;
    case 'activobank':
      return _$createCaptureSourceEnum_activobank;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CreateCaptureSource_Enum> _$createCaptureSourceEnumValues =
    BuiltSet<CreateCaptureSource_Enum>(const <CreateCaptureSource_Enum>[
      _$createCaptureSourceEnum_revolut,
      _$createCaptureSourceEnum_googleWallet,
      _$createCaptureSourceEnum_appleWallet,
      _$createCaptureSourceEnum_activobank,
    ]);

Serializer<CreateCaptureKindEnum> _$createCaptureKindEnumSerializer =
    _$CreateCaptureKindEnumSerializer();
Serializer<CreateCaptureSource_Enum> _$createCaptureSourceEnumSerializer =
    _$CreateCaptureSource_EnumSerializer();

class _$CreateCaptureKindEnumSerializer implements PrimitiveSerializer<CreateCaptureKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'expense': 'expense',
    'income': 'income',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'expense': 'expense',
    'income': 'income',
  };

  @override
  final Iterable<Type> types = const <Type>[CreateCaptureKindEnum];
  @override
  final String wireName = 'CreateCaptureKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    CreateCaptureKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  CreateCaptureKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => CreateCaptureKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$CreateCaptureSource_EnumSerializer
    implements PrimitiveSerializer<CreateCaptureSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'revolut': 'revolut',
    'googleWallet': 'google_wallet',
    'appleWallet': 'apple_wallet',
    'activobank': 'activobank',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'revolut': 'revolut',
    'google_wallet': 'googleWallet',
    'apple_wallet': 'appleWallet',
    'activobank': 'activobank',
  };

  @override
  final Iterable<Type> types = const <Type>[CreateCaptureSource_Enum];
  @override
  final String wireName = 'CreateCaptureSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    CreateCaptureSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  CreateCaptureSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => CreateCaptureSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$CreateCapture extends CreateCapture {
  @override
  final CreateCaptureKindEnum kind;
  @override
  final int amount;
  @override
  final String currency;
  @override
  final String merchant;
  @override
  final DateTime capturedAt;
  @override
  final CreateCaptureSource_Enum source_;

  factory _$CreateCapture([void Function(CreateCaptureBuilder)? updates]) =>
      (CreateCaptureBuilder()..update(updates))._build();

  _$CreateCapture._({
    required this.kind,
    required this.amount,
    required this.currency,
    required this.merchant,
    required this.capturedAt,
    required this.source_,
  }) : super._();
  @override
  CreateCapture rebuild(void Function(CreateCaptureBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateCaptureBuilder toBuilder() => CreateCaptureBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateCapture &&
        kind == other.kind &&
        amount == other.amount &&
        currency == other.currency &&
        merchant == other.merchant &&
        capturedAt == other.capturedAt &&
        source_ == other.source_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, amount.hashCode);
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jc(_$hash, merchant.hashCode);
    _$hash = $jc(_$hash, capturedAt.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateCapture')
          ..add('kind', kind)
          ..add('amount', amount)
          ..add('currency', currency)
          ..add('merchant', merchant)
          ..add('capturedAt', capturedAt)
          ..add('source_', source_))
        .toString();
  }
}

class CreateCaptureBuilder implements Builder<CreateCapture, CreateCaptureBuilder> {
  _$CreateCapture? _$v;

  CreateCaptureKindEnum? _kind;
  CreateCaptureKindEnum? get kind => _$this._kind;
  set kind(CreateCaptureKindEnum? kind) => _$this._kind = kind;

  int? _amount;
  int? get amount => _$this._amount;
  set amount(int? amount) => _$this._amount = amount;

  String? _currency;
  String? get currency => _$this._currency;
  set currency(String? currency) => _$this._currency = currency;

  String? _merchant;
  String? get merchant => _$this._merchant;
  set merchant(String? merchant) => _$this._merchant = merchant;

  DateTime? _capturedAt;
  DateTime? get capturedAt => _$this._capturedAt;
  set capturedAt(DateTime? capturedAt) => _$this._capturedAt = capturedAt;

  CreateCaptureSource_Enum? _source_;
  CreateCaptureSource_Enum? get source_ => _$this._source_;
  set source_(CreateCaptureSource_Enum? source_) => _$this._source_ = source_;

  CreateCaptureBuilder() {
    CreateCapture._defaults(this);
  }

  CreateCaptureBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _amount = $v.amount;
      _currency = $v.currency;
      _merchant = $v.merchant;
      _capturedAt = $v.capturedAt;
      _source_ = $v.source_;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateCapture other) {
    _$v = other as _$CreateCapture;
  }

  @override
  void update(void Function(CreateCaptureBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateCapture build() => _build();

  _$CreateCapture _build() {
    final _$result =
        _$v ??
        _$CreateCapture._(
          kind: BuiltValueNullFieldError.checkNotNull(kind, r'CreateCapture', 'kind'),
          amount: BuiltValueNullFieldError.checkNotNull(amount, r'CreateCapture', 'amount'),
          currency: BuiltValueNullFieldError.checkNotNull(currency, r'CreateCapture', 'currency'),
          merchant: BuiltValueNullFieldError.checkNotNull(merchant, r'CreateCapture', 'merchant'),
          capturedAt: BuiltValueNullFieldError.checkNotNull(
            capturedAt,
            r'CreateCapture',
            'capturedAt',
          ),
          source_: BuiltValueNullFieldError.checkNotNull(source_, r'CreateCapture', 'source_'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
