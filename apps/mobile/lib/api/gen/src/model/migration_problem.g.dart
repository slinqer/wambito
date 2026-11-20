// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_problem.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationProblem extends MigrationProblem {
  @override
  final String type;
  @override
  final String title;
  @override
  final int status;
  @override
  final String code;
  @override
  final String? detail;
  @override
  final MigrationProblemErrors? errors;

  factory _$MigrationProblem([void Function(MigrationProblemBuilder)? updates]) =>
      (MigrationProblemBuilder()..update(updates))._build();

  _$MigrationProblem._({
    required this.type,
    required this.title,
    required this.status,
    required this.code,
    this.detail,
    this.errors,
  }) : super._();
  @override
  MigrationProblem rebuild(void Function(MigrationProblemBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationProblemBuilder toBuilder() => MigrationProblemBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationProblem &&
        type == other.type &&
        title == other.title &&
        status == other.status &&
        code == other.code &&
        detail == other.detail &&
        errors == other.errors;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, errors.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationProblem')
          ..add('type', type)
          ..add('title', title)
          ..add('status', status)
          ..add('code', code)
          ..add('detail', detail)
          ..add('errors', errors))
        .toString();
  }
}

class MigrationProblemBuilder implements Builder<MigrationProblem, MigrationProblemBuilder> {
  _$MigrationProblem? _$v;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  int? _status;
  int? get status => _$this._status;
  set status(int? status) => _$this._status = status;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  MigrationProblemErrorsBuilder? _errors;
  MigrationProblemErrorsBuilder get errors => _$this._errors ??= MigrationProblemErrorsBuilder();
  set errors(MigrationProblemErrorsBuilder? errors) => _$this._errors = errors;

  MigrationProblemBuilder() {
    MigrationProblem._defaults(this);
  }

  MigrationProblemBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _type = $v.type;
      _title = $v.title;
      _status = $v.status;
      _code = $v.code;
      _detail = $v.detail;
      _errors = $v.errors?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationProblem other) {
    _$v = other as _$MigrationProblem;
  }

  @override
  void update(void Function(MigrationProblemBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationProblem build() => _build();

  _$MigrationProblem _build() {
    _$MigrationProblem _$result;
    try {
      _$result =
          _$v ??
          _$MigrationProblem._(
            type: BuiltValueNullFieldError.checkNotNull(type, r'MigrationProblem', 'type'),
            title: BuiltValueNullFieldError.checkNotNull(title, r'MigrationProblem', 'title'),
            status: BuiltValueNullFieldError.checkNotNull(status, r'MigrationProblem', 'status'),
            code: BuiltValueNullFieldError.checkNotNull(code, r'MigrationProblem', 'code'),
            detail: detail,
            errors: _errors?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'errors';
        _errors?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'MigrationProblem', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
