// Port of packages/core/src/suggested-categories.ts.
import 'budget.dart';

/// The languages a suggestion is named in.
enum SuggestionLocale { es, en, it, pt }

class SuggestedCategory {
  const SuggestedCategory({
    required this.key,
    required this.glyph,
    required this.tint,
    required this.kind,
    required this.names,
  });

  /// Stable id of the suggestion (not stored anywhere).
  final String key;

  /// Emoji: saved as the category's `icon`.
  final String glyph;

  /// Mid-tone color: saved as `color`.
  final String tint;
  final CategoryKind kind;

  /// The category's name in each language.
  final Map<SuggestionLocale, String> names;
}

/// The categories every new account starts with and the onboarding's suggestions.
const suggestedCategories = <SuggestedCategory>[
  SuggestedCategory(
    key: 'groceries',
    glyph: '🛒',
    tint: '#ff9f1c',
    kind: CategoryKind.expense,
    names: {
      SuggestionLocale.es: 'Supermercado',
      SuggestionLocale.en: 'Groceries',
      SuggestionLocale.it: 'Supermercato',
      SuggestionLocale.pt: 'Supermercado',
    },
  ),
  SuggestedCategory(
    key: 'eating_out',
    glyph: '🍽️',
    tint: '#ff5c7a',
    kind: CategoryKind.expense,
    names: {
      SuggestionLocale.es: 'Restaurante',
      SuggestionLocale.en: 'Eating out',
      SuggestionLocale.it: 'Ristorante',
      SuggestionLocale.pt: 'Restaurante',
    },
  ),
  SuggestedCategory(
    key: 'home',
    glyph: '🏠',
    tint: '#6d6bff',
    kind: CategoryKind.expense,
    names: {
      SuggestionLocale.es: 'Casa',
      SuggestionLocale.en: 'Home',
      SuggestionLocale.it: 'Casa',
      SuggestionLocale.pt: 'Casa',
    },
  ),
  SuggestedCategory(
    key: 'transport',
    glyph: '🚗',
    tint: '#3fa7ff',
    kind: CategoryKind.expense,
    names: {
      SuggestionLocale.es: 'Transporte',
      SuggestionLocale.en: 'Transport',
      SuggestionLocale.it: 'Trasporti',
      SuggestionLocale.pt: 'Transportes',
    },
  ),
  SuggestedCategory(
    key: 'fun',
    glyph: '⭐',
    tint: '#a66bff',
    kind: CategoryKind.expense,
    names: {
      SuggestionLocale.es: 'Ocio',
      SuggestionLocale.en: 'Fun',
      SuggestionLocale.it: 'Tempo libero',
      SuggestionLocale.pt: 'Lazer',
    },
  ),
  SuggestedCategory(
    key: 'subscriptions',
    glyph: '☂️',
    tint: '#ff8fd8',
    kind: CategoryKind.expense,
    names: {
      SuggestionLocale.es: 'Suscripciones',
      SuggestionLocale.en: 'Subscriptions',
      SuggestionLocale.it: 'Abbonamenti',
      SuggestionLocale.pt: 'Subscrições',
    },
  ),
  SuggestedCategory(
    key: 'health',
    glyph: '❤️',
    tint: '#ffb547',
    kind: CategoryKind.expense,
    names: {
      SuggestionLocale.es: 'Vida',
      SuggestionLocale.en: 'Health',
      SuggestionLocale.it: 'Salute',
      SuggestionLocale.pt: 'Saúde',
    },
  ),
  SuggestedCategory(
    key: 'salary',
    glyph: '💰',
    tint: '#2fd388',
    kind: CategoryKind.income,
    names: {
      SuggestionLocale.es: 'Salario',
      SuggestionLocale.en: 'Salary',
      SuggestionLocale.it: 'Stipendio',
      SuggestionLocale.pt: 'Salário',
    },
  ),
];
