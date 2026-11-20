// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'migration_source_profile.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MigrationSourceProfile extends MigrationSourceProfile {
  @override
  final String timezone;
  @override
  final String locale;
  @override
  final String? onboardingCompletedAt;
  @override
  final String currency;

  factory _$MigrationSourceProfile([void Function(MigrationSourceProfileBuilder)? updates]) =>
      (MigrationSourceProfileBuilder()..update(updates))._build();

  _$MigrationSourceProfile._({
    required this.timezone,
    required this.locale,
    this.onboardingCompletedAt,
    required this.currency,
  }) : super._();
  @override
  MigrationSourceProfile rebuild(void Function(MigrationSourceProfileBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MigrationSourceProfileBuilder toBuilder() => MigrationSourceProfileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MigrationSourceProfile &&
        timezone == other.timezone &&
        locale == other.locale &&
        onboardingCompletedAt == other.onboardingCompletedAt &&
        currency == other.currency;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, onboardingCompletedAt.hashCode);
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MigrationSourceProfile')
          ..add('timezone', timezone)
          ..add('locale', locale)
          ..add('onboardingCompletedAt', onboardingCompletedAt)
          ..add('currency', currency))
        .toString();
  }
}

class MigrationSourceProfileBuilder
    implements Builder<MigrationSourceProfile, MigrationSourceProfileBuilder> {
  _$MigrationSourceProfile? _$v;

  String? _timezone;
  String? get timezone => _$this._timezone;
  set timezone(String? timezone) => _$this._timezone = timezone;

  String? _locale;
  String? get locale => _$this._locale;
  set locale(String? locale) => _$this._locale = locale;

  String? _onboardingCompletedAt;
  String? get onboardingCompletedAt => _$this._onboardingCompletedAt;
  set onboardingCompletedAt(String? onboardingCompletedAt) =>
      _$this._onboardingCompletedAt = onboardingCompletedAt;

  String? _currency;
  String? get currency => _$this._currency;
  set currency(String? currency) => _$this._currency = currency;

  MigrationSourceProfileBuilder() {
    MigrationSourceProfile._defaults(this);
  }

  MigrationSourceProfileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _timezone = $v.timezone;
      _locale = $v.locale;
      _onboardingCompletedAt = $v.onboardingCompletedAt;
      _currency = $v.currency;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MigrationSourceProfile other) {
    _$v = other as _$MigrationSourceProfile;
  }

  @override
  void update(void Function(MigrationSourceProfileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MigrationSourceProfile build() => _build();

  _$MigrationSourceProfile _build() {
    final _$result =
        _$v ??
        _$MigrationSourceProfile._(
          timezone: BuiltValueNullFieldError.checkNotNull(
            timezone,
            r'MigrationSourceProfile',
            'timezone',
          ),
          locale: BuiltValueNullFieldError.checkNotNull(
            locale,
            r'MigrationSourceProfile',
            'locale',
          ),
          onboardingCompletedAt: onboardingCompletedAt,
          currency: BuiltValueNullFieldError.checkNotNull(
            currency,
            r'MigrationSourceProfile',
            'currency',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
