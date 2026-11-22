// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const TransactionStatusEnum _$transactionStatusEnum_paid = const TransactionStatusEnum._('paid');
const TransactionStatusEnum _$transactionStatusEnum_pending = const TransactionStatusEnum._(
  'pending',
);

TransactionStatusEnum _$transactionStatusEnumValueOf(String name) {
  switch (name) {
    case 'paid':
      return _$transactionStatusEnum_paid;
    case 'pending':
      return _$transactionStatusEnum_pending;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<TransactionStatusEnum> _$transactionStatusEnumValues =
    BuiltSet<TransactionStatusEnum>(const <TransactionStatusEnum>[
      _$transactionStatusEnum_paid,
      _$transactionStatusEnum_pending,
    ]);

const TransactionSource_Enum _$transactionSourceEnum_app = const TransactionSource_Enum._('app');
const TransactionSource_Enum _$transactionSourceEnum_web = const TransactionSource_Enum._('web');
const TransactionSource_Enum _$transactionSourceEnum_widget = const TransactionSource_Enum._(
  'widget',
);
const TransactionSource_Enum _$transactionSourceEnum_mcp = const TransactionSource_Enum._('mcp');
const TransactionSource_Enum _$transactionSourceEnum_import_ = const TransactionSource_Enum._(
  'import_',
);
const TransactionSource_Enum _$transactionSourceEnum_recurrence = const TransactionSource_Enum._(
  'recurrence',
);
const TransactionSource_Enum _$transactionSourceEnum_capture = const TransactionSource_Enum._(
  'capture',
);

TransactionSource_Enum _$transactionSourceEnumValueOf(String name) {
  switch (name) {
    case 'app':
      return _$transactionSourceEnum_app;
    case 'web':
      return _$transactionSourceEnum_web;
    case 'widget':
      return _$transactionSourceEnum_widget;
    case 'mcp':
      return _$transactionSourceEnum_mcp;
    case 'import_':
      return _$transactionSourceEnum_import_;
    case 'recurrence':
      return _$transactionSourceEnum_recurrence;
    case 'capture':
      return _$transactionSourceEnum_capture;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<TransactionSource_Enum> _$transactionSourceEnumValues =
    BuiltSet<TransactionSource_Enum>(const <TransactionSource_Enum>[
      _$transactionSourceEnum_app,
      _$transactionSourceEnum_web,
      _$transactionSourceEnum_widget,
      _$transactionSourceEnum_mcp,
      _$transactionSourceEnum_import_,
      _$transactionSourceEnum_recurrence,
      _$transactionSourceEnum_capture,
    ]);

Serializer<TransactionStatusEnum> _$transactionStatusEnumSerializer =
    _$TransactionStatusEnumSerializer();
Serializer<TransactionSource_Enum> _$transactionSourceEnumSerializer =
    _$TransactionSource_EnumSerializer();

class _$TransactionStatusEnumSerializer implements PrimitiveSerializer<TransactionStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'paid': 'paid',
    'pending': 'pending',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'paid': 'paid',
    'pending': 'pending',
  };

  @override
  final Iterable<Type> types = const <Type>[TransactionStatusEnum];
  @override
  final String wireName = 'TransactionStatusEnum';

  @override
  Object serialize(
    Serializers serializers,
    TransactionStatusEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  TransactionStatusEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => TransactionStatusEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$TransactionSource_EnumSerializer implements PrimitiveSerializer<TransactionSource_Enum> {
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
  final Iterable<Type> types = const <Type>[TransactionSource_Enum];
  @override
  final String wireName = 'TransactionSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    TransactionSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  TransactionSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => TransactionSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$Transaction extends Transaction {
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
  final TransactionStatusEnum status;
  @override
  final String? note;
  @override
  final String categoryId;
  @override
  final String? recurrenceId;
  @override
  final String? importId;
  @override
  final TransactionSource_Enum source_;
  @override
  final bool needsReview;
  @override
  final String? captureSource;
  @override
  final String createdAt;
  @override
  final String updatedAt;

  factory _$Transaction([void Function(TransactionBuilder)? updates]) =>
      (TransactionBuilder()..update(updates))._build();

  _$Transaction._({
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
  Transaction rebuild(void Function(TransactionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TransactionBuilder toBuilder() => TransactionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Transaction &&
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
    return (newBuiltValueToStringHelper(r'Transaction')
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

class TransactionBuilder implements Builder<Transaction, TransactionBuilder> {
  _$Transaction? _$v;

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

  TransactionStatusEnum? _status;
  TransactionStatusEnum? get status => _$this._status;
  set status(TransactionStatusEnum? status) => _$this._status = status;

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

  TransactionSource_Enum? _source_;
  TransactionSource_Enum? get source_ => _$this._source_;
  set source_(TransactionSource_Enum? source_) => _$this._source_ = source_;

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

  TransactionBuilder() {
    Transaction._defaults(this);
  }

  TransactionBuilder get _$this {
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
  void replace(Transaction other) {
    _$v = other as _$Transaction;
  }

  @override
  void update(void Function(TransactionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Transaction build() => _build();

  _$Transaction _build() {
    final _$result =
        _$v ??
        _$Transaction._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'Transaction', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(name, r'Transaction', 'name'),
          amount: BuiltValueNullFieldError.checkNotNull(amount, r'Transaction', 'amount'),
          currency: BuiltValueNullFieldError.checkNotNull(currency, r'Transaction', 'currency'),
          date: BuiltValueNullFieldError.checkNotNull(date, r'Transaction', 'date'),
          status: BuiltValueNullFieldError.checkNotNull(status, r'Transaction', 'status'),
          note: note,
          categoryId: BuiltValueNullFieldError.checkNotNull(
            categoryId,
            r'Transaction',
            'categoryId',
          ),
          recurrenceId: recurrenceId,
          importId: importId,
          source_: BuiltValueNullFieldError.checkNotNull(source_, r'Transaction', 'source_'),
          needsReview: BuiltValueNullFieldError.checkNotNull(
            needsReview,
            r'Transaction',
            'needsReview',
          ),
          captureSource: captureSource,
          createdAt: BuiltValueNullFieldError.checkNotNull(createdAt, r'Transaction', 'createdAt'),
          updatedAt: BuiltValueNullFieldError.checkNotNull(updatedAt, r'Transaction', 'updatedAt'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
