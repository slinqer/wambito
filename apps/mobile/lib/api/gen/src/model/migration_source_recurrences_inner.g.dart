// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_source_recurrences_inner.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MigrationSourceRecurrencesInnerFrequencyEnum
_$migrationSourceRecurrencesInnerFrequencyEnum_monthly =
    const MigrationSourceRecurrencesInnerFrequencyEnum._('monthly');
const MigrationSourceRecurrencesInnerFrequencyEnum
_$migrationSourceRecurrencesInnerFrequencyEnum_yearly =
    const MigrationSourceRecurrencesInnerFrequencyEnum._('yearly');

MigrationSourceRecurrencesInnerFrequencyEnum _$migrationSourceRecurrencesInnerFrequencyEnumValueOf(
  String name,
) {
  switch (name) {
    case 'monthly':
      return _$migrationSourceRecurrencesInnerFrequencyEnum_monthly;
    case 'yearly':
      return _$migrationSourceRecurrencesInnerFrequencyEnum_yearly;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<MigrationSourceRecurrencesInnerFrequencyEnum>
_$migrationSourceRecurrencesInnerFrequencyEnumValues =
    BuiltSet<MigrationSourceRecurrencesInnerFrequencyEnum>(
      const <MigrationSourceRecurrencesInnerFrequencyEnum>[
        _$migrationSourceRecurrencesInnerFrequencyEnum_monthly,
        _$migrationSourceRecurrencesInnerFrequencyEnum_yearly,
      ],
    );

Serializer<MigrationSourceRecurrencesInnerFrequencyEnum>
_$migrationSourceRecurrencesInnerFrequencyEnumSerializer =
    _$MigrationSourceRecurrencesInnerFrequencyEnumSerializer();

class _$MigrationSourceRecurrencesInnerFrequencyEnumSerializer
    implements PrimitiveSerializer<MigrationSourceRecurrencesInnerFrequencyEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'monthly': 'monthly',
    'yearly': 'yearly',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'monthly': 'monthly',
    'yearly': 'yearly',
  };

  @override
  final Iterable<Type> types = const <Type>[MigrationSourceRecurrencesInnerFrequencyEnum];
  @override
  final String wireName = 'MigrationSourceRecurrencesInnerFrequencyEnum';

  @override
  Object serialize(
    Serializers serializers,
    MigrationSourceRecurrencesInnerFrequencyEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MigrationSourceRecurrencesInnerFrequencyEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MigrationSourceRecurrencesInnerFrequencyEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$MigrationSourceRecurrencesInner extends MigrationSourceRecurrencesInner {
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
  final MigrationSourceRecurrencesInnerFrequencyEnum frequency;
  @override
  final int dayOfMonth;
  @override
  final int? monthOfYear;
  @override
  final String startDate;
  @override
  final String? endDate;
  @override
  final String createdAt;
  @override
  final String updatedAt;

  factory _$MigrationSourceRecurrencesInner([
    void Function(MigrationSourceRecurrencesInnerBuilder)? updates,
  ]) => (MigrationSourceRecurrencesInnerBuilder()..update(updates))._build();

  _$MigrationSourceRecurrencesInner._({
    required this.id,
    required this.accountId,
    required this.categoryId,
    required this.name,
    required this.amount,
    required this.frequency,
    required this.dayOfMonth,
    this.monthOfYear,
    required this.startDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
  }) : super._();
  @override
  MigrationSourceRecurrencesInner rebuild(
    void Function(MigrationSourceRecurrencesInnerBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  MigrationSourceRecurrencesInnerBuilder toBuilder() =>
      MigrationSourceRecurrencesInnerBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationSourceRecurrencesInner &&
        id == other.id &&
        accountId == other.accountId &&
        categoryId == other.categoryId &&
        name == other.name &&
        amount == other.amount &&
        frequency == other.frequency &&
        dayOfMonth == other.dayOfMonth &&
        monthOfYear == other.monthOfYear &&
        startDate == other.startDate &&
        endDate == other.endDate &&
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
    _$hash = $jc(_$hash, frequency.hashCode);
    _$hash = $jc(_$hash, dayOfMonth.hashCode);
    _$hash = $jc(_$hash, monthOfYear.hashCode);
    _$hash = $jc(_$hash, startDate.hashCode);
    _$hash = $jc(_$hash, endDate.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationSourceRecurrencesInner')
          ..add('id', id)
          ..add('accountId', accountId)
          ..add('categoryId', categoryId)
          ..add('name', name)
          ..add('amount', amount)
          ..add('frequency', frequency)
          ..add('dayOfMonth', dayOfMonth)
          ..add('monthOfYear', monthOfYear)
          ..add('startDate', startDate)
          ..add('endDate', endDate)
          ..add('createdAt', createdAt)
          ..add('updatedAt', updatedAt))
        .toString();
  }
}

class MigrationSourceRecurrencesInnerBuilder
    implements Builder<MigrationSourceRecurrencesInner, MigrationSourceRecurrencesInnerBuilder> {
  _$MigrationSourceRecurrencesInner? _$v;

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

  MigrationSourceRecurrencesInnerFrequencyEnum? _frequency;
  MigrationSourceRecurrencesInnerFrequencyEnum? get frequency => _$this._frequency;
  set frequency(MigrationSourceRecurrencesInnerFrequencyEnum? frequency) =>
      _$this._frequency = frequency;

  int? _dayOfMonth;
  int? get dayOfMonth => _$this._dayOfMonth;
  set dayOfMonth(int? dayOfMonth) => _$this._dayOfMonth = dayOfMonth;

  int? _monthOfYear;
  int? get monthOfYear => _$this._monthOfYear;
  set monthOfYear(int? monthOfYear) => _$this._monthOfYear = monthOfYear;

  String? _startDate;
  String? get startDate => _$this._startDate;
  set startDate(String? startDate) => _$this._startDate = startDate;

  String? _endDate;
  String? get endDate => _$this._endDate;
  set endDate(String? endDate) => _$this._endDate = endDate;

  String? _createdAt;
  String? get createdAt => _$this._createdAt;
  set createdAt(String? createdAt) => _$this._createdAt = createdAt;

  String? _updatedAt;
  String? get updatedAt => _$this._updatedAt;
  set updatedAt(String? updatedAt) => _$this._updatedAt = updatedAt;

  MigrationSourceRecurrencesInnerBuilder() {
    MigrationSourceRecurrencesInner._defaults(this);
  }

  MigrationSourceRecurrencesInnerBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _accountId = $v.accountId;
      _categoryId = $v.categoryId;
      _name = $v.name;
      _amount = $v.amount;
      _frequency = $v.frequency;
      _dayOfMonth = $v.dayOfMonth;
      _monthOfYear = $v.monthOfYear;
      _startDate = $v.startDate;
      _endDate = $v.endDate;
      _createdAt = $v.createdAt;
      _updatedAt = $v.updatedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationSourceRecurrencesInner other) {
    _$v = other as _$MigrationSourceRecurrencesInner;
  }

  @override
  void update(void Function(MigrationSourceRecurrencesInnerBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationSourceRecurrencesInner build() => _build();

  _$MigrationSourceRecurrencesInner _build() {
    final _$result =
        _$v ??
        _$MigrationSourceRecurrencesInner._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'MigrationSourceRecurrencesInner', 'id'),
          accountId: BuiltValueNullFieldError.checkNotNull(
            accountId,
            r'MigrationSourceRecurrencesInner',
            'accountId',
          ),
          categoryId: BuiltValueNullFieldError.checkNotNull(
            categoryId,
            r'MigrationSourceRecurrencesInner',
            'categoryId',
          ),
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'MigrationSourceRecurrencesInner',
            'name',
          ),
          amount: BuiltValueNullFieldError.checkNotNull(
            amount,
            r'MigrationSourceRecurrencesInner',
            'amount',
          ),
          frequency: BuiltValueNullFieldError.checkNotNull(
            frequency,
            r'MigrationSourceRecurrencesInner',
            'frequency',
          ),
          dayOfMonth: BuiltValueNullFieldError.checkNotNull(
            dayOfMonth,
            r'MigrationSourceRecurrencesInner',
            'dayOfMonth',
          ),
          monthOfYear: monthOfYear,
          startDate: BuiltValueNullFieldError.checkNotNull(
            startDate,
            r'MigrationSourceRecurrencesInner',
            'startDate',
          ),
          endDate: endDate,
          createdAt: BuiltValueNullFieldError.checkNotNull(
            createdAt,
            r'MigrationSourceRecurrencesInner',
            'createdAt',
          ),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
            updatedAt,
            r'MigrationSourceRecurrencesInner',
            'updatedAt',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
