# Privacy policy (draft)

> Draft, kept in line with the live policy at `/privacy` (`legal.privacy` in
> `apps/web/app/i18n/messages/*.json`). True from the switch day (E2E stage 5,
> `docs/deploy/switch-day.md`); its dates are filled in on that day.

Wambito keeps the data you give it so it can show you your budget. Your finances are end-to-end
encrypted: they are encrypted on your device, with a key only you and your devices hold, and the
server keeps them only as ciphertext it cannot read.

- **End-to-end encrypted (the server cannot read it):** transactions (deleted ones kept for
  restore included), categories, budgets, recurring payments, the category you gave each merchant,
  your settings (currency among them), and what you import.
- **What the server still sees (metadata):** your email; the public part of your passkeys; how many
  records of each type you have, their size in coarse buckets, when they change and which are deleted; the profile
  columns: time zone, language, whether onboarding is done; the platform and version of your app
  and the last day you opened it (active days are counted per day without a user id); the names of
  the devices you link; the permissions of the AI assistants you connect; for each session, the kind
  of browser or app. **No IP address is stored**: not on sessions, not in rate limits (kept in
  memory) and not in the access log, which keeps only when, which page and the status, without query
  strings or headers.
- **The web caveat:** the web app's code comes from our server each time it loads, so whoever
  controlled the server could serve code that reads the key while the page is open. The Android app,
  signed (and reproducibly built on F-Droid), does not have that weakness.
- **Assistants:** an AI assistant you connect through MCP can read and change your data only with
  the permissions you approve. While it is connected, the MCP server opens what it asks for in
  memory, during each request, with a key the assistant carries; it never stores that key or any
  plaintext. Revoking it cuts it at once. The assistant's company handles what it reads under its
  own policy.
- **Guests (no email):** stored encrypted like everyone else; deleted after 12 months unused, or 24
  months when protected with a recovery key or a passkey.
- **What we don't do:** we don't sell your data, show ads, run trackers or analytics, or share it
  with third parties, except the services we need to run: the server, the backups and the email
  provider that delivers your sign-in codes.
- **Imports:** from a Budge export we keep only your transactions and category names, encrypted on
  your device. Budge's user id and account balances are discarded.
- **Backups:** a daily backup on the server and an age-encrypted copy in Cloudflare R2, none older
  than 14 days. Accounts created before end-to-end encryption moved to it on SWITCH_DATE; backups
  from before that day still hold those finances in a form we could read, and the last of them
  deletes itself on SWITCH_DATE_PLUS_14. After that date no plaintext copy of anyone's finances exists.
- **Your rights (Ley 1581):** you can download all your data from Settings (your device makes the
  file, since only your devices can open your finances) and delete your account at any time. We
  delete your account and all your records right away; backups that include them delete themselves
  within 14 days. A request to us covers everything else we hold.
