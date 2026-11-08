// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_results.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PushResults extends PushResults {
  @override
  final BuiltList<PushResult> results;

  factory _$PushResults([void Function(PushResultsBuilder)? updates]) =>
      (PushResultsBuilder()..update(updates))._build();

  _$PushResults._({required this.results}) : super._();
  @override
  PushResults rebuild(void Function(PushResultsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PushResultsBuilder toBuilder() => PushResultsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PushResults && results == other.results;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, results.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PushResults')..add('results', results)).toString();
  }
}

class PushResultsBuilder implements Builder<PushResults, PushResultsBuilder> {
  _$PushResults? _$v;

  ListBuilder<PushResult>? _results;
  ListBuilder<PushResult> get results => _$this._results ??= ListBuilder<PushResult>();
  set results(ListBuilder<PushResult>? results) => _$this._results = results;

  PushResultsBuilder() {
    PushResults._defaults(this);
  }

  PushResultsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _results = $v.results.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PushResults other) {
    _$v = other as _$PushResults;
  }

  @override
  void update(void Function(PushResultsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PushResults build() => _build();

  _$PushResults _build() {
    _$PushResults _$result;
    try {
      _$result = _$v ?? _$PushResults._(results: results.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'results';
        results.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(r'PushResults', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
