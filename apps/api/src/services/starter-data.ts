import { SUGGESTED_CATEGORIES, type SuggestionLocale } from "@wambito/core";
import { accounts, categories, type Db, withUser } from "@wambito/db";

/**
 * What a new plain account starts with: the default account "Main" in `currency` and the
 * suggested categories, named in `locale`. The user-create hook in `auth.ts` gives it to every
 * plain sign-up; `seed:e2e-plain-user` gives it to the plain users the web e2e seeds.
 */
export async function giveStarterData(
  db: Db,
  userId: string,
  { currency, locale }: { currency: string; locale: SuggestionLocale },
): Promise<void> {
  await withUser(db, userId, async (tx) => {
    await tx.insert(accounts).values({ userId, name: "Main", currency, isDefault: true });
    await tx.insert(categories).values(
      SUGGESTED_CATEGORIES.map((suggestion, sortOrder) => ({
        userId,
        name: suggestion.names[locale],
        kind: suggestion.kind,
        icon: suggestion.glyph,
        color: suggestion.tint,
        sortOrder,
      })),
    );
  });
}
