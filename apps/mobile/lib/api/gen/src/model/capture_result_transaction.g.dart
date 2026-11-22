// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'capture_result_transaction.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const CaptureResultTransactionStatusEnum _$captureResultTransactionStatusEnum_paid =
    const CaptureResultTransactionStatusEnum._('paid');
const CaptureResultTransactionStatusEnum _$captureResultTransactionStatusEnum_pending =
    const CaptureResultTransactionStatusEnum._('pending');

CaptureResultTransactionStatusEnum _$captureResultTransactionStatusEnumValueOf(String name) {
  switch (name) {
    case 'paid':
      return _$captureResultTransactionStatusEnum_paid;
    case 'pending':
      return _$captureResultTransactionStatusEnum_pending;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CaptureResultTransactionStatusEnum> _$captureResultTransactionStatusEnumValues =
    BuiltSet<CaptureResultTransactionStatusEnum>(const <CaptureResultTransactionStatusEnum>[
      _$captureResultTransactionStatusEnum_paid,
      _$captureResultTransactionStatusEnum_pending,
    ]);

const CaptureResultTransactionSource_Enum _$captureResultTransactionSourceEnum_app =
    const CaptureResultTransactionSource_Enum._('app');
const CaptureResultTransactionSource_Enum _$captureResultTransactionSourceEnum_web =
    const CaptureResultTransactionSource_Enum._('web');
const CaptureResultTransactionSource_Enum _$captureResultTransactionSourceEnum_widget =
    const CaptureResultTransactionSource_Enum._('widget');
const CaptureResultTransactionSource_Enum _$captureResultTransactionSourceEnum_mcp =
    const CaptureResultTransactionSource_Enum._('mcp');
const CaptureResultTransactionSource_Enum _$captureResultTransactionSourceEnum_import_ =
    const CaptureResultTransactionSource_Enum._('import_');
const CaptureResultTransactionSource_Enum _$captureResultTransactionSourceEnum_recurrence =
    const CaptureResultTransactionSource_Enum._('recurrence');
const CaptureResultTransactionSource_Enum _$captureResultTransactionSourceEnum_capture =
    const CaptureResultTransactionSource_Enum._('capture');

CaptureResultTransactionSource_Enum _$captureResultTransactionSourceEnumValueOf(String name) {
  switch (name) {
    case 'app':
      return _$captureResultTransactionSourceEnum_app;
    case 'web':
      return _$captureResultTransactionSourceEnum_web;
    case 'widget':
      return _$captureResultTransactionSourceEnum_widget;
    case 'mcp':
      return _$captureResultTransactionSourceEnum_mcp;
    case 'import_':
      return _$captureResultTransactionSourceEnum_import_;
    case 'recurrence':
      return _$captureResultTransactionSourceEnum_recurrence;
    case 'capture':
      return _$captureResultTransactionSourceEnum_capture;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<CaptureResultTransactionSource_Enum> _$captureResultTransactionSourceEnumValues =
    BuiltSet<CaptureResultTransactionSource_Enum>(const <CaptureResultTransactionSource_Enum>[
      _$captureResultTransactionSourceEnum_app,
      _$captureResultTransactionSourceEnum_web,
      _$captureResultTransactionSourceEnum_widget,
      _$captureResultTransactionSourceEnum_mcp,
      _$captureResultTransactionSourceEnum_import_,
      _$captureResultTransactionSourceEnum_recurrence,
      _$captureResultTransactionSourceEnum_capture,
    ]);

Serializer<CaptureResultTransactionStatusEnum> _$captureResultTransactionStatusEnumSerializer =
    _$CaptureResultTransactionStatusEnumSerializer();
Serializer<CaptureResultTransactionSource_Enum> _$captureResultTransactionSourceEnumSerializer =
    _$CaptureResultTransactionSource_EnumSerializer();

class _$CaptureResultTransactionStatusEnumSerializer
    implements PrimitiveSerializer<CaptureResultTransactionStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'paid': 'paid',
    'pending': 'pending',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'paid': 'paid',
    'pending': 'pending',
  };

  @override
  final Iterable<Type> types = const <Type>[CaptureResultTransactionStatusEnum];
  @override
  final String wireName = 'CaptureResultTransactionStatusEnum';

  @override
  Object serialize(
    Serializers serializers,
    CaptureResultTransactionStatusEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  CaptureResultTransactionStatusEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => CaptureResultTransactionStatusEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$CaptureResultTransactionSource_EnumSerializer
    implements PrimitiveSerializer<CaptureResultTransactionSource_Enum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'app': 'app',
    'web': 'web',
    'widget': 'widget',
    'mcp': 'mcp',
    'import_': 'import',
    'recurrence': 'recurrence',
    'capture': 'capture',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'app': 'app',
    'web': 'web',
    'widget': 'widget',
    'mcp': 'mcp',
    'import': 'import_',
    'recurrence': 'recurrence',
    'capture': 'capture',
  };

  @override
  final Iterable<Type> types = const <Type>[CaptureResultTransactionSource_Enum];
  @override
  final String wireName = 'CaptureResultTransactionSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    CaptureResultTransactionSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  CaptureResultTransactionSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => CaptureResultTransactionSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$CaptureResultTransaction extends CaptureResultTransaction {
  @override
  final String id;
  @override
  final String name;
  @override
  final int amount;
  @override
  final String currency;
  @override
  final String date;
  @override
  final CaptureResultTransactionStatusEnum status;
  @override
  final String? note;
  @override
  final String categoryId;
  @override
  final String? recurrenceId;
  @override
  final String? importId;
  @override
  final CaptureResultTransactionSource_Enum source_;
  @override
  final bool needsReview;
  @override
  final String? captureSource;
  @override
  final String createdAt;
  @override
  final String updatedAt;

  factory _$CaptureResultTransaction([void Function(CaptureResultTransactionBuilder)? updates]) =>
      (CaptureResultTransactionBuilder()..update(updates))._build();

  _$CaptureResultTransaction._({
    required this.id,
    required this.name,
    required this.amount,
    required this.currency,
    required this.date,
    required this.status,
    this.note,
    required this.categoryId,
    this.recurrenceId,
    this.importId,
    required this.source_,
    required this.needsReview,
    this.captureSource,
    required this.createdAt,
    required this.updatedAt,
  }) : super._();
  @override
  CaptureResultTransaction rebuild(void Function(CaptureResultTransactionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CaptureResultTransactionBuilder toBuilder() => CaptureResultTransactionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CaptureResultTransaction &&
        id == other.id &&
        name == other.name &&
        amount == other.amount &&
        currency == other.currency &&
        date == other.date &&
        status == other.status &&
        note == other.note &&
        categoryId == other.categoryId &&
        recurrenceId == other.recurrenceId &&
        importId == other.importId &&
        source_ == other.source_ &&
        needsReview == other.needsReview &&
        captureSource == other.captureSource &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, amount.hashCode);
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, recurrenceId.hashCode);
    _$hash = $jc(_$hash, importId.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, needsReview.hashCode);
    _$hash = $jc(_$hash, captureSource.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CaptureResultTransaction')
          ..add('id', id)
          ..add('name', name)
          ..add('amount', amount)
          ..add('currency', currency)
          ..add('date', date)
          ..add('status', status)
          ..add('note', note)
          ..add('categoryId', categoryId)
          ..add('recurrenceId', recurrenceId)
          ..add('importId', importId)
          ..add('source_', source_)
          ..add('needsReview', needsReview)
          ..add('captureSource', captureSource)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class CaptureResultTransactionBuilder
    implements Builder<CaptureResultTransaction, CaptureResultTransactionBuilder> {
  _$CaptureResultTransaction? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _amount;
  int? get amount => _$this._amount;
  set amount(int? amount) => _$this._amount = amount;

  String? _currency;
  String? get currency => _$this._currency;
  set currency(String? currency) => _$this._currency = currency;

  String? _date;
  String? get date => _$this._date;
  set date(String? date) => _$this._date = date;

  CaptureResultTransactionStatusEnum? _status;
  CaptureResultTransactionStatusEnum? get status => _$this._status;
  set status(CaptureResultTransactionStatusEnum? status) => _$this._status = status;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

  String? _recurrenceId;
  String? get recurrenceId => _$this._recurrenceId;
  set recurrenceId(String? recurrenceId) => _$this._recurrenceId = recurrenceId;

  String? _importId;
  String? get importId => _$this._importId;
  set importId(String? importId) => _$this._importId = importId;

  CaptureResultTransactionSource_Enum? _source_;
  CaptureResultTransactionSource_Enum? get source_ => _$this._source_;
  set source_(CaptureResultTransactionSource_Enum? source_) => _$this._source_ = source_;

  bool? _needsReview;
  bool? get needsReview => _$this._needsReview;
  set needsReview(bool? needsReview) => _$this._needsReview = needsReview;

  String? _captureSource;
  String? get captureSource => _$this._captureSource;
  set captureSource(String? captureSource) => _$this._captureSource = captureSource;

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  String? _updatedAt;
  String? get updatedAt => _$this._updatedAt;
  set updatedAt(String? updatedAt) => _$this._updatedAt = updatedAt;

  CaptureResultTransactionBuilder() {
    CaptureResultTransaction._defaults(this);
  }

  CaptureResultTransactionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _name = $v.name;
      _amount = $v.amount;
      _currency = $v.currency;
      _date = $v.date;
      _status = $v.status;
      _note = $v.note;
      _categoryId = $v.categoryId;
      _recurrenceId = $v.recurrenceId;
      _importId = $v.importId;
      _source_ = $v.source_;
      _needsReview = $v.needsReview;
      _captureSource = $v.captureSource;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CaptureResultTransaction other) {
    _$v = other as _$CaptureResultTransaction;
  }

  @override
  void update(void Function(CaptureResultTransactionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CaptureResultTransaction build() => _build();

  _$CaptureResultTransaction _build() {
    final _$result =
        _$v ??
        _$CaptureResultTransaction._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'CaptureResultTransaction', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(name, r'CaptureResultTransaction', 'name'),
          amount: BuiltValueNullFieldError.checkNotNull(
            amount,
            r'CaptureResultTransaction',
            'amount',
          ),
          currency: BuiltValueNullFieldError.checkNotNull(
            currency,
            r'CaptureResultTransaction',
            'currency',
          ),
          date: BuiltValueNullFieldError.checkNotNull(date, r'CaptureResultTransaction', 'date'),
          status: BuiltValueNullFieldError.checkNotNull(
            status,
            r'CaptureResultTransaction',
            'status',
          ),
          note: note,
          categoryId: BuiltValueNullFieldError.checkNotNull(
            categoryId,
            r'CaptureResultTransaction',
            'categoryId',
          ),
          recurrenceId: recurrenceId,
          importId: importId,
          source_: BuiltValueNullFieldError.checkNotNull(
            source_,
            r'CaptureResultTransaction',
            'source_',
          ),
          needsReview: BuiltValueNullFieldError.checkNotNull(
            needsReview,
            r'CaptureResultTransaction',
            'needsReview',
          ),
          captureSource: captureSource,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'CaptureResultTransaction',
            'createdAt',
          ),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
            updatedAt,
            r'CaptureResultTransaction',
            'updatedAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
