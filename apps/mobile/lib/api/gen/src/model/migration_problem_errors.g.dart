// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_problem_errors.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationProblemErrors extends MigrationProblemErrors {
  @override
  final MigrationCounts server;
  @override
  final MigrationCounts records;
  @override
  final MigrationCounts client;
  @override
  final BuiltList<MigrationProblemErrorsMissingInner> missing;

  factory _$MigrationProblemErrors([void Function(MigrationProblemErrorsBuilder)? updates]) =>
      (MigrationProblemErrorsBuilder()..update(updates))._build();

  _$MigrationProblemErrors._({
    required this.server,
    required this.records,
    required this.client,
    required this.missing,
  }) : super._();
  @override
  MigrationProblemErrors rebuild(void Function(MigrationProblemErrorsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationProblemErrorsBuilder toBuilder() => MigrationProblemErrorsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationProblemErrors &&
        server == other.server &&
        records == other.records &&
        client == other.client &&
        missing == other.missing;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, server.hashCode);
    _$hash = $jc(_$hash, records.hashCode);
    _$hash = $jc(_$hash, client.hashCode);
    _$hash = $jc(_$hash, missing.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationProblemErrors')
          ..add('server', server)
          ..add('records', records)
          ..add('client', client)
          ..add('missing', missing))
        .toString();
  }
}

class MigrationProblemErrorsBuilder
    implements Builder<MigrationProblemErrors, MigrationProblemErrorsBuilder> {
  _$MigrationProblemErrors? _$v;

  MigrationCountsBuilder? _server;
  MigrationCountsBuilder get server => _$this._server ??= MigrationCountsBuilder();
  set server(MigrationCountsBuilder? server) => _$this._server = server;

  MigrationCountsBuilder? _records;
  MigrationCountsBuilder get records => _$this._records ??= MigrationCountsBuilder();
  set records(MigrationCountsBuilder? records) => _$this._records = records;

  MigrationCountsBuilder? _client;
  MigrationCountsBuilder get client => _$this._client ??= MigrationCountsBuilder();
  set client(MigrationCountsBuilder? client) => _$this._client = client;

  ListBuilder<MigrationProblemErrorsMissingInner>? _missing;
  ListBuilder<MigrationProblemErrorsMissingInner> get missing =>
      _$this._missing ??= ListBuilder<MigrationProblemErrorsMissingInner>();
  set missing(ListBuilder<MigrationProblemErrorsMissingInner>? missing) =>
      _$this._missing = missing;

  MigrationProblemErrorsBuilder() {
    MigrationProblemErrors._defaults(this);
  }

  MigrationProblemErrorsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _server = $v.server.toBuilder();
      _records = $v.records.toBuilder();
      _client = $v.client.toBuilder();
      _missing = $v.missing.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationProblemErrors other) {
    _$v = other as _$MigrationProblemErrors;
  }

  @override
  void update(void Function(MigrationProblemErrorsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationProblemErrors build() => _build();

  _$MigrationProblemErrors _build() {
    _$MigrationProblemErrors _$result;
    try {
      _$result =
          _$v ??
          _$MigrationProblemErrors._(
            server: server.build(),
            records: records.build(),
            client: client.build(),
            missing: missing.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'server';
        server.build();
        _$failedField = 'records';
        records.build();
        _$failedField = 'client';
        client.build();
        _$failedField = 'missing';
        missing.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'MigrationProblemErrors', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
