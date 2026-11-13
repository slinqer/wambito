// Port of packages/core/src/default-currency.ts.

/// Countries of Europe (the EU, the EEA, the UK, Switzerland and the Balkans): their default is EUR.
const _europe = {
  'AD', 'AL', 'AT', 'BA', 'BE', 'BG', 'CH', 'CY', 'CZ', 'DE', 'DK', 'EE', 'ES', 'FI', 'FR', 'GB', //
  'GR', 'HR', 'HU', 'IE', 'IS', 'IT', 'LI', 'LT', 'LU', 'LV', 'MC', 'MD', 'ME', 'MK', 'MT', 'NL', //
  'NO', 'PL', 'PT', 'RO', 'RS', 'SE', 'SI', 'SK', 'SM', 'UA', 'VA', 'XK',
};

/// The currency a new account starts with, from the device's time zone and, when known, its
/// region (ISO 3166 alpha-2): Colombia → COP; Europe → EUR; anywhere else → USD.
String defaultCurrencyFor(String timezone, [String? region]) {
  final country = region?.toUpperCase();
  if (country == 'CO' || timezone == 'America/Bogota') return 'COP';
  if ((country != null && _europe.contains(country)) || timezone.startsWith('Europe/')) {
    return 'EUR';
  }
  return 'USD';
}
