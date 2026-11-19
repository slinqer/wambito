// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_source_transactions_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MigrationSourceTransactionsInnerStatusEnum _$migrationSourceTransactionsInnerStatusEnum_paid =
    const MigrationSourceTransactionsInnerStatusEnum._('paid');
const MigrationSourceTransactionsInnerStatusEnum
_$migrationSourceTransactionsInnerStatusEnum_pending =
    const MigrationSourceTransactionsInnerStatusEnum._('pending');

MigrationSourceTransactionsInnerStatusEnum _$migrationSourceTransactionsInnerStatusEnumValueOf(
  String name,
) {
  switch (name) {
    case 'paid':
      return _$migrationSourceTransactionsInnerStatusEnum_paid;
    case 'pending':
      return _$migrationSourceTransactionsInnerStatusEnum_pending;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MigrationSourceTransactionsInnerStatusEnum>
_$migrationSourceTransactionsInnerStatusEnumValues =
    BuiltSet<MigrationSourceTransactionsInnerStatusEnum>(
      const <MigrationSourceTransactionsInnerStatusEnum>[
        _$migrationSourceTransactionsInnerStatusEnum_paid,
        _$migrationSourceTransactionsInnerStatusEnum_pending,
      ],
    );

const MigrationSourceTransactionsInnerSource_Enum _$migrationSourceTransactionsInnerSourceEnum_app =
    const MigrationSourceTransactionsInnerSource_Enum._('app');
const MigrationSourceTransactionsInnerSource_Enum _$migrationSourceTransactionsInnerSourceEnum_web =
    const MigrationSourceTransactionsInnerSource_Enum._('web');
const MigrationSourceTransactionsInnerSource_Enum
_$migrationSourceTransactionsInnerSourceEnum_widget =
    const MigrationSourceTransactionsInnerSource_Enum._('widget');
const MigrationSourceTransactionsInnerSource_Enum _$migrationSourceTransactionsInnerSourceEnum_mcp =
    const MigrationSourceTransactionsInnerSource_Enum._('mcp');
const MigrationSourceTransactionsInnerSource_Enum
_$migrationSourceTransactionsInnerSourceEnum_import_ =
    const MigrationSourceTransactionsInnerSource_Enum._('import_');
const MigrationSourceTransactionsInnerSource_Enum
_$migrationSourceTransactionsInnerSourceEnum_recurrence =
    const MigrationSourceTransactionsInnerSource_Enum._('recurrence');
const MigrationSourceTransactionsInnerSource_Enum
_$migrationSourceTransactionsInnerSourceEnum_capture =
    const MigrationSourceTransactionsInnerSource_Enum._('capture');

MigrationSourceTransactionsInnerSource_Enum _$migrationSourceTransactionsInnerSourceEnumValueOf(
  String name,
) {
  switch (name) {
    case 'app':
      return _$migrationSourceTransactionsInnerSourceEnum_app;
    case 'web':
      return _$migrationSourceTransactionsInnerSourceEnum_web;
    case 'widget':
      return _$migrationSourceTransactionsInnerSourceEnum_widget;
    case 'mcp':
      return _$migrationSourceTransactionsInnerSourceEnum_mcp;
    case 'import_':
      return _$migrationSourceTransactionsInnerSourceEnum_import_;
    case 'recurrence':
      return _$migrationSourceTransactionsInnerSourceEnum_recurrence;
    case 'capture':
      return _$migrationSourceTransactionsInnerSourceEnum_capture;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MigrationSourceTransactionsInnerSource_Enum>
_$migrationSourceTransactionsInnerSourceEnumValues =
    BuiltSet<MigrationSourceTransactionsInnerSource_Enum>(
      const <MigrationSourceTransactionsInnerSource_Enum>[
        _$migrationSourceTransactionsInnerSourceEnum_app,
        _$migrationSourceTransactionsInnerSourceEnum_web,
        _$migrationSourceTransactionsInnerSourceEnum_widget,
        _$migrationSourceTransactionsInnerSourceEnum_mcp,
        _$migrationSourceTransactionsInnerSourceEnum_import_,
        _$migrationSourceTransactionsInnerSourceEnum_recurrence,
        _$migrationSourceTransactionsInnerSourceEnum_capture,
      ],
    );

Serializer<MigrationSourceTransactionsInnerStatusEnum>
_$migrationSourceTransactionsInnerStatusEnumSerializer =
    _$MigrationSourceTransactionsInnerStatusEnumSerializer();
Serializer<MigrationSourceTransactionsInnerSource_Enum>
_$migrationSourceTransactionsInnerSourceEnumSerializer =
    _$MigrationSourceTransactionsInnerSource_EnumSerializer();

class _$MigrationSourceTransactionsInnerStatusEnumSerializer
    implements PrimitiveSerializer<MigrationSourceTransactionsInnerStatusEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'paid': 'paid',
    'pending': 'pending',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'paid': 'paid',
    'pending': 'pending',
  };

  @override
  final Iterable<Type> types = const <Type>[MigrationSourceTransactionsInnerStatusEnum];
  @override
  final String wireName = 'MigrationSourceTransactionsInnerStatusEnum';

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceTransactionsInnerStatusEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MigrationSourceTransactionsInnerStatusEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MigrationSourceTransactionsInnerStatusEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$MigrationSourceTransactionsInnerSource_EnumSerializer
    implements PrimitiveSerializer<MigrationSourceTransactionsInnerSource_Enum> {
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
  final Iterable<Type> types = const <Type>[MigrationSourceTransactionsInnerSource_Enum];
  @override
  final String wireName = 'MigrationSourceTransactionsInnerSource_Enum';

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceTransactionsInnerSource_Enum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MigrationSourceTransactionsInnerSource_Enum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MigrationSourceTransactionsInnerSource_Enum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$MigrationSourceTransactionsInner extends MigrationSourceTransactionsInner {
  @override
  final String id;
  @override
  final String accountId;
  @override
  final String categoryId;
  @override
  final String name;
  @override
  final int amount;
  @override
  final String currency;
  @override
  final String date;
  @override
  final MigrationSourceTransactionsInnerStatusEnum status;
  @override
  final String? note;
  @override
  final String? recurrenceId;
  @override
  final String? occurrenceMonth;
  @override
  final String? importId;
  @override
  final MigrationSourceTransactionsInnerSource_Enum source_;
  @override
  final String? externalHash;
  @override
  final bool needsReview;
  @override
  final String? captureSource;
  @override
  final String? capturedAt;
  @override
  final String? captureMerchantKey;
  @override
  final String? deletedAt;
  @override
  final String createdAt;
  @override
  final String updatedAt;

  factory _$MigrationSourceTransactionsInner([
    void Function(MigrationSourceTransactionsInnerBuilder)? updates,
  ]) => (MigrationSourceTransactionsInnerBuilder()..update(updates))._build();

  _$MigrationSourceTransactionsInner._({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.name,
    required this.amount,
    required this.currency,
    required this.date,
    required this.status,
    this.note,
    this.recurrenceId,
    this.occurrenceMonth,
    this.importId,
    required this.source_,
    this.externalHash,
    required this.needsReview,
    this.captureSource,
    this.capturedAt,
    this.captureMerchantKey,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  }) : super._();
  @override
  MigrationSourceTransactionsInner rebuild(
    void Function(MigrationSourceTransactionsInnerBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MigrationSourceTransactionsInnerBuilder toBuilder() =>
      MigrationSourceTransactionsInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationSourceTransactionsInner &&
        id == other.id &&
        accountId == other.accountId &&
        categoryId == other.categoryId &&
        name == other.name &&
        amount == other.amount &&
        currency == other.currency &&
        date == other.date &&
        status == other.status &&
        note == other.note &&
        recurrenceId == other.recurrenceId &&
        occurrenceMonth == other.occurrenceMonth &&
        importId == other.importId &&
        source_ == other.source_ &&
        externalHash == other.externalHash &&
        needsReview == other.needsReview &&
        captureSource == other.captureSource &&
        capturedAt == other.capturedAt &&
        captureMerchantKey == other.captureMerchantKey &&
        deletedAt == other.deletedAt &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, accountId.hashCode);
    _$hash = $jc(_$hash, categoryId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, amount.hashCode);
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, recurrenceId.hashCode);
    _$hash = $jc(_$hash, occurrenceMonth.hashCode);
    _$hash = $jc(_$hash, importId.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, externalHash.hashCode);
    _$hash = $jc(_$hash, needsReview.hashCode);
    _$hash = $jc(_$hash, captureSource.hashCode);
    _$hash = $jc(_$hash, capturedAt.hashCode);
    _$hash = $jc(_$hash, captureMerchantKey.hashCode);
    _$hash = $jc(_$hash, deletedAt.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationSourceTransactionsInner')
          ..add('id', id)
          ..add('accountId', accountId)
          ..add('categoryId', categoryId)
          ..add('name', name)
          ..add('amount', amount)
          ..add('currency', currency)
          ..add('date', date)
          ..add('status', status)
          ..add('note', note)
          ..add('recurrenceId', recurrenceId)
          ..add('occurrenceMonth', occurrenceMonth)
          ..add('importId', importId)
          ..add('source_', source_)
          ..add('externalHash', externalHash)
          ..add('needsReview', needsReview)
          ..add('captureSource', captureSource)
          ..add('capturedAt', capturedAt)
          ..add('captureMerchantKey', captureMerchantKey)
          ..add('deletedAt', deletedAt)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class MigrationSourceTransactionsInnerBuilder
    implements Builder<MigrationSourceTransactionsInner, MigrationSourceTransactionsInnerBuilder> {
  _$MigrationSourceTransactionsInner? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _accountId;
  String? get accountId => _$this._accountId;
  set accountId(String? accountId) => _$this._accountId = accountId;

  String? _categoryId;
  String? get categoryId => _$this._categoryId;
  set categoryId(String? categoryId) => _$this._categoryId = categoryId;

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

  MigrationSourceTransactionsInnerStatusEnum? _status;
  MigrationSourceTransactionsInnerStatusEnum? get status => _$this._status;
  set status(MigrationSourceTransactionsInnerStatusEnum? status) => _$this._status = status;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  String? _recurrenceId;
  String? get recurrenceId => _$this._recurrenceId;
  set recurrenceId(String? recurrenceId) => _$this._recurrenceId = recurrenceId;

  String? _occurrenceMonth;
  String? get occurrenceMonth => _$this._occurrenceMonth;
  set occurrenceMonth(String? occurrenceMonth) => _$this._occurrenceMonth = occurrenceMonth;

  String? _importId;
  String? get importId => _$this._importId;
  set importId(String? importId) => _$this._importId = importId;

  MigrationSourceTransactionsInnerSource_Enum? _source_;
  MigrationSourceTransactionsInnerSource_Enum? get source_ => _$this._source_;
  set source_(MigrationSourceTransactionsInnerSource_Enum? source_) => _$this._source_ = source_;

  String? _externalHash;
  String? get externalHash => _$this._externalHash;
  set externalHash(String? externalHash) => _$this._externalHash = externalHash;

  bool? _needsReview;
  bool? get needsReview => _$this._needsReview;
  set needsReview(bool? needsReview) => _$this._needsReview = needsReview;

  String? _captureSource;
  String? get captureSource => _$this._captureSource;
  set captureSource(String? captureSource) => _$this._captureSource = captureSource;

  String? _capturedAt;
  String? get capturedAt => _$this._capturedAt;
  set capturedAt(String? capturedAt) => _$this._capturedAt = capturedAt;

  String? _captureMerchantKey;
  String? get captureMerchantKey => _$this._captureMerchantKey;
  set captureMerchantKey(String? captureMerchantKey) =>
      _$this._captureMerchantKey = captureMerchantKey;

  String? _deletedAt;
  String? get deletedAt => _$this._deletedAt;
  set deletedAt(String? deletedAt) => _$this._deletedAt = deletedAt;

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  String? _updatedAt;
  String? get updatedAt => _$this._updatedAt;
  set updatedAt(String? updatedAt) => _$this._updatedAt = updatedAt;

  MigrationSourceTransactionsInnerBuilder() {
    MigrationSourceTransactionsInner._defaults(this);
  }

  MigrationSourceTransactionsInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _accountId = $v.accountId;
      _categoryId = $v.categoryId;
      _name = $v.name;
      _amount = $v.amount;
      _currency = $v.currency;
      _date = $v.date;
      _status = $v.status;
      _note = $v.note;
      _recurrenceId = $v.recurrenceId;
      _occurrenceMonth = $v.occurrenceMonth;
      _importId = $v.importId;
      _source_ = $v.source_;
      _externalHash = $v.externalHash;
      _needsReview = $v.needsReview;
      _captureSource = $v.captureSource;
      _capturedAt = $v.capturedAt;
      _captureMerchantKey = $v.captureMerchantKey;
      _deletedAt = $v.deletedAt;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationSourceTransactionsInner other) {
    _$v = other as _$MigrationSourceTransactionsInner;
  }

  @override
  void update(void Function(MigrationSourceTransactionsInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationSourceTransactionsInner build() => _build();

  _$MigrationSourceTransactionsInner _build() {
    final _$result =
        _$v ??
        _$MigrationSourceTransactionsInner._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'MigrationSourceTransactionsInner', 'id'),
          accountId: BuiltValueNullFieldError.checkNotNull(
            accountId,
            r'MigrationSourceTransactionsInner',
            'accountId',
          ),
          categoryId: BuiltValueNullFieldError.checkNotNull(
            categoryId,
            r'MigrationSourceTransactionsInner',
            'categoryId',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'MigrationSourceTransactionsInner',
            'name',
          ),
          amount: BuiltValueNullFieldError.checkNotNull(
            amount,
            r'MigrationSourceTransactionsInner',
            'amount',
          ),
          currency: BuiltValueNullFieldError.checkNotNull(
            currency,
            r'MigrationSourceTransactionsInner',
            'currency',
          ),
          date: BuiltValueNullFieldError.checkNotNull(
            date,
            r'MigrationSourceTransactionsInner',
            'date',
          ),
          status: BuiltValueNullFieldError.checkNotNull(
            status,
            r'MigrationSourceTransactionsInner',
            'status',
          ),
          note: note,
          recurrenceId: recurrenceId,
          occurrenceMonth: occurrenceMonth,
          importId: importId,
          source_: BuiltValueNullFieldError.checkNotNull(
            source_,
            r'MigrationSourceTransactionsInner',
            'source_',
          ),
          externalHash: externalHash,
          needsReview: BuiltValueNullFieldError.checkNotNull(
            needsReview,
            r'MigrationSourceTransactionsInner',
            'needsReview',
          ),
          captureSource: captureSource,
          capturedAt: capturedAt,
          captureMerchantKey: captureMerchantKey,
          deletedAt: deletedAt,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'MigrationSourceTransactionsInner',
            'createdAt',
          ),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
            updatedAt,
            r'MigrationSourceTransactionsInner',
            'updatedAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
