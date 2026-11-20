// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ProfileEncryptionEnum _$profileEncryptionEnum_plain = const ProfileEncryptionEnum._('plain');
const ProfileEncryptionEnum _$profileEncryptionEnum_preview = const ProfileEncryptionEnum._(
  'preview',
);

ProfileEncryptionEnum _$profileEncryptionEnumValueOf(String name) {
  switch (name) {
    case 'plain':
      return _$profileEncryptionEnum_plain;
    case 'preview':
      return _$profileEncryptionEnum_preview;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ProfileEncryptionEnum> _$profileEncryptionEnumValues =
    BuiltSet<ProfileEncryptionEnum>(const <ProfileEncryptionEnum>[
      _$profileEncryptionEnum_plain,
      _$profileEncryptionEnum_preview,
    ]);

const ProfileMigrationEnum _$profileMigrationEnum_available = const ProfileMigrationEnum._(
  'available',
);
const ProfileMigrationEnum _$profileMigrationEnum_inProgress = const ProfileMigrationEnum._(
  'inProgress',
);

ProfileMigrationEnum _$profileMigrationEnumValueOf(String name) {
  switch (name) {
    case 'available':
      return _$profileMigrationEnum_available;
    case 'inProgress':
      return _$profileMigrationEnum_inProgress;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ProfileMigrationEnum> _$profileMigrationEnumValues = BuiltSet<ProfileMigrationEnum>(
  const <ProfileMigrationEnum>[_$profileMigrationEnum_available, _$profileMigrationEnum_inProgress],
);

Serializer<ProfileEncryptionEnum> _$profileEncryptionEnumSerializer =
    _$ProfileEncryptionEnumSerializer();
Serializer<ProfileMigrationEnum> _$profileMigrationEnumSerializer =
    _$ProfileMigrationEnumSerializer();

class _$ProfileEncryptionEnumSerializer implements PrimitiveSerializer<ProfileEncryptionEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'plain': 'plain',
    'preview': 'preview',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'plain': 'plain',
    'preview': 'preview',
  };

  @override
  final Iterable<Type> types = const <Type>[ProfileEncryptionEnum];
  @override
  final String wireName = 'ProfileEncryptionEnum';

  @override
  Object serialize(
    Serializers serializers,
    ProfileEncryptionEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ProfileEncryptionEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ProfileEncryptionEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$ProfileMigrationEnumSerializer implements PrimitiveSerializer<ProfileMigrationEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'available': 'available',
    'inProgress': 'in_progress',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'available': 'available',
    'in_progress': 'inProgress',
  };

  @override
  final Iterable<Type> types = const <Type>[ProfileMigrationEnum];
  @override
  final String wireName = 'ProfileMigrationEnum';

  @override
  Object serialize(
    Serializers serializers,
    ProfileMigrationEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ProfileMigrationEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ProfileMigrationEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$Profile extends Profile {
  @override
  final String id;
  @override
  final String email;
  @override
  final String timezone;
  @override
  final String locale;
  @override
  final String? onboardingCompletedAt;
  @override
  final String currency;
  @override
  final bool isAnonymous;
  @override
  final ProfileEncryptionEnum encryption;
  @override
  final ProfileMigrationEnum? migration;

  factory _$Profile([void Function(ProfileBuilder)? updates]) =>
      (ProfileBuilder()..update(updates))._build();

  _$Profile._({
    required this.id,
    required this.email,
    required this.timezone,
    required this.locale,
    this.onboardingCompletedAt,
    required this.currency,
    required this.isAnonymous,
    required this.encryption,
    this.migration,
  }) : super._();
  @override
  Profile rebuild(void Function(ProfileBuilder) updates) => (toBuilder()..update(updates)).build();

  @override
  ProfileBuilder toBuilder() => ProfileBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Profile &&
        id == other.id &&
        email == other.email &&
        timezone == other.timezone &&
        locale == other.locale &&
        onboardingCompletedAt == other.onboardingCompletedAt &&
        currency == other.currency &&
        isAnonymous == other.isAnonymous &&
        encryption == other.encryption &&
        migration == other.migration;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, email.hashCode);
    _$hash = $jc(_$hash, timezone.hashCode);
    _$hash = $jc(_$hash, locale.hashCode);
    _$hash = $jc(_$hash, onboardingCompletedAt.hashCode);
    _$hash = $jc(_$hash, currency.hashCode);
    _$hash = $jc(_$hash, isAnonymous.hashCode);
    _$hash = $jc(_$hash, encryption.hashCode);
    _$hash = $jc(_$hash, migration.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'Profile')
          ..add('id', id)
          ..add('email', email)
          ..add('timezone', timezone)
          ..add('locale', locale)
          ..add('onboardingCompletedAt', onboardingCompletedAt)
          ..add('currency', currency)
          ..add('isAnonymous', isAnonymous)
          ..add('encryption', encryption)
          ..add('migration', migration))
        .toString();
  }
}

class ProfileBuilder implements Builder<Profile, ProfileBuilder> {
  _$Profile? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _email;
  String? get email => _$this._email;
  set email(String? email) => _$this._email = email;

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

  bool? _isAnonymous;
  bool? get isAnonymous => _$this._isAnonymous;
  set isAnonymous(bool? isAnonymous) => _$this._isAnonymous = isAnonymous;

  ProfileEncryptionEnum? _encryption;
  ProfileEncryptionEnum? get encryption => _$this._encryption;
  set encryption(ProfileEncryptionEnum? encryption) => _$this._encryption = encryption;

  ProfileMigrationEnum? _migration;
  ProfileMigrationEnum? get migration => _$this._migration;
  set migration(ProfileMigrationEnum? migration) => _$this._migration = migration;

  ProfileBuilder() {
    Profile._defaults(this);
  }

  ProfileBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _email = $v.email;
      _timezone = $v.timezone;
      _locale = $v.locale;
      _onboardingCompletedAt = $v.onboardingCompletedAt;
      _currency = $v.currency;
      _isAnonymous = $v.isAnonymous;
      _encryption = $v.encryption;
      _migration = $v.migration;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Profile other) {
    _$v = other as _$Profile;
  }

  @override
  void update(void Function(ProfileBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Profile build() => _build();

  _$Profile _build() {
    final _$result =
        _$v ??
        _$Profile._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'Profile', 'id'),
          email: BuiltValueNullFieldError.checkNotNull(email, r'Profile', 'email'),
          timezone: BuiltValueNullFieldError.checkNotNull(timezone, r'Profile', 'timezone'),
          locale: BuiltValueNullFieldError.checkNotNull(locale, r'Profile', 'locale'),
          onboardingCompletedAt: onboardingCompletedAt,
          currency: BuiltValueNullFieldError.checkNotNull(currency, r'Profile', 'currency'),
          isAnonymous: BuiltValueNullFieldError.checkNotNull(
            isAnonymous,
            r'Profile',
            'isAnonymous',
          ),
          encryption: BuiltValueNullFieldError.checkNotNull(encryption, r'Profile', 'encryption'),
          migration: migration,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
