# Italian and Portuguese: sample for review

About 40 representative lines per language, for the founder to read before release. Every line is taken from the web catalogs (`apps/web/app/i18n/messages`) or the sign-in and claim emails (`apps/api/src/emails/sign-in.ts`), so what you read here is what ships. The app and the widget (Flutter ARB, Android strings) follow in the next step and reuse the same wording.

What to check:

- Wambi's voice: warm, plain, positive, short sentences, as in Spanish.
- Italian uses the "tu" form.
- Portuguese is European: "telemóvel", "registar", "ligação", "palavra-passe", "Definições", the "tu" form, no "estar + gerund".
- "Wambito" and "Wambi" are never translated. "Lukas" and "palos" (Colombian slang) do not appear in Italian or Portuguese: "Tus lukas, por fin claras" becomes "I tuoi soldi, finalmente chiari" and "O teu dinheiro, finalmente claro".
- Placeholders (`{amount}`, `{name}`, `{daysLeft}`...) and plural rules are kept as they are.

Questions for you:

1. Italian bottom bar: "Impostazioni" is 12 letters (Spanish "Ajustes" is 7). It is the standard word; if it truncates at 360 px we can shorten it to "Opzioni".
2. Portuguese for a transaction is "movimento" (the bank word in Portugal), income is "receita" and a budget is "orçamento".
3. Italian for a budget is "budget" (what Italian finance apps say), income is "entrata".

## Landing

| key | es | it | pt |
|---|---|---|---|
| `landing.hero.annotation` | ¡Gratis, y siempre lo será! | Gratis, e lo sarà sempre! | Grátis, e vai ser sempre! |
| `landing.hero.headline` | Tus <mark>lukas</mark>, por fin claras. | I tuoi <mark>soldi</mark>, finalmente chiari. | O teu <mark>dinheiro</mark>, finalmente claro. |
| `landing.hero.description` | <lead>Wambito es tu presupuesto, y te va a dar gusto cuidarlo.</lead> Anota un gasto en segundos y mira en qué se va cada luka. | <lead>Wambito è il tuo budget, e ti farà piacere prendertene cura.</lead> Annota una spesa in pochi secondi e guarda dove va ogni centesimo. | <lead>Wambito é o teu orçamento, e vais gostar de cuidar dele.</lead> Regista uma despesa em segundos e vê para onde vai cada cêntimo. |
| `landing.hero.cta` | Empieza ahora | Inizia ora | Começa agora |
| `landing.hero.cta_demo` | Pruébalo sin cuenta | Provala senza account | Experimenta sem conta |
| `landing.hero.perks` | Gratis para siempre · <github>Código abierto</github> · Sin contraseñas | Gratis per sempre · <github>Open source</github> · Senza password | Grátis para sempre · <github>Código aberto</github> · Sem palavras-passe |
| `landing.how.log.title` | Anota en segundos | Annota in pochi secondi | Regista em segundos |
| `landing.how.log.body` | Tocas ＋, escribes el monto y listo: menos de cinco segundos desde que abres la app. Wambi lo celebra contigo. | Tocchi ＋, scrivi l'importo e fatto: meno di cinque secondi da quando apri l'app. Wambi festeggia con te. | Tocas em ＋, escreves o valor e já está: menos de cinco segundos desde que abres a app. Wambi celebra contigo. |
| `landing.how.budgets.title` | Presupuestos que te avisan | Budget che ti avvisano | Orçamentos que te avisam |
| `landing.how.budgets.body` | Ponle un tope a cada categoría. Las barras se llenan con lo que gastas y cambian de color antes de que te pases, no después. | Metti un tetto a ogni categoria. Le barre si riempiono con quello che spendi e cambiano colore prima che tu sfori, non dopo. | Põe um limite em cada categoria. As barras enchem com o que gastas e mudam de cor antes de te excederes, não depois. |
| `landing.faq.passwords.a` | Porque no la necesitas. Entras con un código de 6 dígitos o un enlace que te llega al correo y, si quieres, con una passkey: tu huella, tu cara o el bloqueo de tu teléfono. No hay contraseña que recordar. | Perché non ti serve. Entri con un codice di 6 cifre o con un link che ti arriva via email e, se vuoi, con una passkey: la tua impronta, il tuo viso o il blocco del telefono. Nessuna password da ricordare. | Porque não precisas dela. Entras com um código de 6 dígitos ou com uma ligação que te chega ao email e, se quiseres, com uma passkey: a tua impressão digital, a tua cara ou o bloqueio do telemóvel. Não há palavra-passe para decorar. |
| `landing.faq.privacy.a` | Tus datos viajan cifrados y nunca los vendemos ni los compartimos con anunciantes. Puedes exportarlos o borrar tu cuenta cuando quieras. El código es abierto: cualquiera puede leer el código que los maneja. | I tuoi dati viaggiano cifrati e non li vendiamo né li condividiamo mai con gli inserzionisti. Puoi esportarli o cancellare il tuo account quando vuoi. Il codice è open source: chiunque può leggere il codice che li gestisce. | Os teus dados viajam cifrados e nunca os vendemos nem os partilhamos com anunciantes. Podes exportá-los ou apagar a tua conta quando quiseres. O código é aberto: qualquer pessoa pode ler o código que os trata. |
| `landing.faq.free.a` | Sí, y lo será siempre. Wambito es gratis y de código abierto: todo el código está en <github>GitHub</github> y cualquiera puede revisarlo. No te pedimos tarjeta. | Sì, e lo sarà sempre. Wambito è gratis e open source: tutto il codice è su <github>GitHub</github> e chiunque può controllarlo. Non ti chiediamo la carta. | Sim, e vai ser sempre. Wambito é grátis e de código aberto: todo o código está no <github>GitHub</github> e qualquer pessoa o pode rever. Não te pedimos cartão. |
| `roadmap.items.multi_expense.body` | «Gasté 15 mil en almuerzo y 3 mil en Uber» y quedan los dos anotados. | «Ho speso 15 per il pranzo e 3 per Uber» e restano annotate entrambe. | «Gastei 15 no almoço e 3 no Uber» e ficam as duas registadas. |

## Home, tabs and navigation

| key | es | it | pt |
|---|---|---|---|
| `home.view.transactions` | Movimientos | Movimenti | Movimentos |
| `home.view.budgets` | Categorías | Categorie | Categorias |
| `nav.home` | Inicio | Home | Início |
| `nav.insights` | Análisis | Analisi | Análise |
| `nav.recurring` | Recurrentes | Ricorrenti | Recorrentes |
| `nav.categories` | Categorías | Categorie | Categorias |
| `nav.settings` | Ajustes | Impostazioni | Definições |
| `transaction.add_expense` | Agregar gasto | Aggiungi spesa | Adicionar despesa |
| `transaction.title_expense` | Nuevo gasto | Nuova spesa | Nova despesa |
| `common.save` | Guardar | Salva | Guardar |
| `home.remaining_label` | Te quedan este mes | Ti restano questo mese | Restam-te este mês |
| `home.over_label` | Te pasaste este mes | Hai sforato questo mese | Passaste do limite este mês |
| `category_row.remaining` | Quedan {amount} | Restano {amount} | Restam {amount} |
| `category_row.over` | Te pasaste {amount} | Hai sforato di {amount} | Passaste {amount} do limite |
| `onboarding.budgets.title` | ¿Cuánto quieres gastar al mes? | Quanto vuoi spendere al mese? | Quanto queres gastar por mês? |
| `onboarding.budgets.lead` | Ponle un presupuesto a cada categoría. Puedes dejar alguna vacía y ponerlo después. | Dai un budget a ogni categoria. Puoi lasciarne qualcuna vuota e metterlo dopo. | Define um orçamento para cada categoria. Podes deixar alguma vazia e preenchê-la depois. |
| `home.nudge_budgets_lead` | Así Wambito te avisa antes de que te pases. Toca una categoría y ponle un monto. | Così Wambito ti avvisa prima che tu sfori. Tocca una categoria e metti un importo. | Assim Wambito avisa-te antes de te excederes. Toca numa categoria e define um valor. |

## Wambi's messages

| key | es | it | pt |
|---|---|---|---|
| `home.wambi_empty` | ¡Hola! Anota tu primer gasto con el ＋ y yo llevo la cuenta. | Ciao! Annota la tua prima spesa con il ＋ e io tengo il conto. | Olá! Regista a tua primeira despesa com o ＋ e eu faço as contas. |
| `home.wambi_over_total` | Este mes vas {over} por encima de tus presupuestos. Aquí lo tienes todo a la vista. | Questo mese sei {over} sopra i tuoi budget. Qui hai tutto sotto gli occhi. | Este mês estás {over} acima dos teus orçamentos. Aqui tens tudo à vista. |
| `wambi.first_of_day.1` | ¡«{name}» es tu primer apunte del día! Así se empieza. | «{name}» è la tua prima voce di oggi! Così si comincia. | «{name}» é o teu primeiro registo do dia! É assim que se começa. |
| `wambi.on_track.1` | Vas muy bien: te quedan {remaining} para {daysLeft, plural, one {# día} other {# días}}. | Stai andando benissimo: ti restano {remaining} per {daysLeft, plural, one {# giorno} other {# giorni}}. | Estás a ir muito bem: restam-te {remaining} para {daysLeft, plural, one {# dia} other {# dias}}. |
| `wambi.near_limit.1` | Cuidado, a {category} solo le quedan {remaining}. | Attenzione, a {category} restano solo {remaining}. | Cuidado, em {category} só restam {remaining}. |
| `wambi.over_budget.1` | En {category} vas {over} por encima. Nada grave: ya lo sabes. | In {category} sei sopra di {over}. Niente di grave: ora lo sai. | Em {category} estás {over} acima. Nada de grave: já sabes. |
| `wambi.income_received.1` | ¡Entró dinero! «{name}»: {amount} más en tu cuenta. | È entrato del denaro! «{name}»: {amount} in più sul tuo conto. | Entrou dinheiro! «{name}»: mais {amount} na tua conta. |
| `wambi.pending_paid.1` | Pagaste «{name}»: {amount}. ¡Qué alivio! | Hai pagato «{name}»: {amount}. Che sollievo! | Pagaste «{name}»: {amount}. Que alívio! |
| `wambi.month_last_day.2` | Hoy cierra el mes con {remaining} a tu favor. ¡Casi lo logras! | Oggi il mese chiude con {remaining} a tuo favore. Ce l'hai quasi fatta! | Hoje o mês fecha com {remaining} a teu favor. Quase lá! |
| `wambi.month_closed_green.2` | Cerraste con {remaining} de sobra. ¡Eso merece celebrarse! | Hai chiuso con {remaining} in più. Questo merita una festa! | Fechaste com {remaining} de sobra. Isso merece uma festa! |

## Errors

| key | es | it | pt |
|---|---|---|---|
| `errors.generic` | Algo salió mal. Inténtalo de nuevo en un momento. | Qualcosa è andato storto. Riprova tra un momento. | Algo correu mal. Tenta de novo daqui a um momento. |
| `errors.network_error` | Sin conexión. Revisa tu internet e inténtalo de nuevo. | Nessuna connessione. Controlla internet e riprova. | Sem ligação. Verifica a tua internet e tenta de novo. |
| `errors.invalid_code` | Ese código no es correcto. Revísalo e inténtalo otra vez. | Questo codice non è corretto. Controllalo e riprova. | Esse código não está correto. Verifica-o e tenta outra vez. |
| `errors.too_many_requests` | Pediste muchos códigos seguidos. Espera unos minutos e inténtalo otra vez. | Hai chiesto troppi codici di fila. Aspetta qualche minuto e riprova. | Pediste muitos códigos seguidos. Espera uns minutos e tenta outra vez. |
| `errors.sign_in_not_allowed` | Wambito todavía no está abierto al público. Si quieres probarlo, escríbele a quien te invitó. | Wambito non è ancora aperta al pubblico. Se vuoi provarla, scrivi a chi ti ha invitato. | Wambito ainda não está aberta ao público. Se a quiseres experimentar, escreve a quem te convidou. |

## Sign-in

| key | es | it | pt |
|---|---|---|---|
| `sign_in.title` | Entra a Wambito | Entra in Wambito | Entra em Wambito |
| `sign_in.lead` | Sin contraseñas: te mandamos un código a tu correo. | Niente password: ti mandiamo un codice via email. | Sem palavras-passe: enviamos-te um código por email. |
| `sign_in.send_code` | Enviar código | Invia codice | Enviar código |
| `passkey_offer.title` | ¿Entrar con tu huella la próxima vez? | Entrare con l'impronta la prossima volta? | Entrar com a impressão digital da próxima vez? |

## Settings

| key | es | it | pt |
|---|---|---|---|
| `settings.title` | Ajustes | Impostazioni | Definições |
| `settings.preferences` | Preferencias | Preferenze | Preferências |
| `settings.currency.hint` | Puedes cambiarla hasta tu primer movimiento. | Puoi cambiarla fino al tuo primo movimento. | Podes mudá-la até ao teu primeiro movimento. |
| `settings.delete.lead` | Borramos tu cuenta y todos tus movimientos de inmediato. Las copias de seguridad que los incluyan se borran solas en 14 días. | Cancelliamo subito il tuo account e tutti i tuoi movimenti. Le copie di sicurezza che li includono si cancellano da sole entro 14 giorni. | Apagamos a tua conta e todos os teus movimentos de imediato. As cópias de segurança que os incluem apagam-se sozinhas em 14 dias. |
| `settings.delete.action` | Eliminar mi cuenta | Elimina il mio account | Eliminar a minha conta |

## Emails

The sign-in email and the claim email (a guest saving their progress, no link).

| key | es | it | pt |
|---|---|---|---|
| `email.sign_in.subject` | Tu código de Wambito: 123456 | Il tuo codice Wambito: 123456 | O teu código Wambito: 123456 |
| `email.sign_in.heading` | ¡Hola! Este es tu código para entrar | Ciao! Questo è il tuo codice per entrare | Olá! Este é o teu código para entrar |
| `email.sign_in.lead` | Escríbelo en Wambito, o toca el botón para entrar directo. | Scrivilo in Wambito, oppure tocca il pulsante per entrare subito. | Escreve-o em Wambito ou toca no botão para entrares logo. |
| `email.sign_in.button` | ENTRAR A WAMBITO | ENTRA IN WAMBITO | ENTRAR EM WAMBITO |
| `email.sign_in.expiry` | El código y el enlace vencen en 10 minutos. | Il codice e il link scadono tra 10 minuti. | O código e a ligação expiram dentro de 10 minutos. |
| `email.sign_in.ignore` | Si no pediste este correo, ignóralo: nadie puede entrar sin este código. | Se non hai chiesto questa email, ignorala: nessuno può entrare senza questo codice. | Se não pediste este email, ignora-o: ninguém consegue entrar sem este código. |
| `email.claim.subject` | Tu código para guardar tu progreso: 123456 | Il tuo codice per salvare i tuoi progressi: 123456 | O teu código para guardares o teu progresso: 123456 |
| `email.claim.lead` | Escríbelo en Wambito para guardar tu progreso con este correo. | Scrivilo in Wambito per salvare i tuoi progressi con questa email. | Escreve-o em Wambito para guardar o teu progresso com este email. |

## App

The app's own words, which the web does not have: the capture sheet, guest accounts, the voice and server settings, the widget and the two notices (Flutter ARB and Android strings), plus the store short description. Keys are ARB keys, `values*/strings.xml` names, or the fastlane file. Notes for the founder:

- Voice dictation and the sentence parser now exist in all four languages. Portuguese voice is labelled beta (`captureOfferTitle`, `captureOfferBody` and the store copy) until the recorded spike passes (`docs/superpowers/reports/2026-10-26-it-pt-voice-spike.md`). `captureNoVoiceYet` stays for a language without a model, so it no longer names a language.
- The example sentence («15 pranzo, 3 uber», «15 almoço, 3 uber») is what typing understands now: amount, then name, separated by commas.
- Store short descriptions say "Libera" / "Livre" (free as in freedom, like the Spanish "Libre").

### Quick capture (say it or type it)

| key | es | it | pt |
|---|---|---|---|
| `captureTitle` | Dilo o escríbelo | Dillo o scrivilo | Diz ou escreve |
| `captureListeningPrompt` | ¿En qué gastaste? | Per cosa hai speso? | Em que gastaste? |
| `captureListeningNote` | Te escucho aquí mismo: lo que dices no sale de tu teléfono. | Ti ascolto qui: quello che dici non esce dal telefono. | Ouço-te aqui mesmo: o que dizes não sai do teu telemóvel. |
| `captureFieldLabel` | Escribe lo que gastaste | Scrivi quello che hai speso | Escreve o que gastaste |
| `captureNoVoiceYet` | Todavía no te escucho en este idioma, así que escríbelo aquí. | Per ora non ti ascolto in italiano, quindi scrivilo qui. | Por agora não te ouço em português, por isso escreve aqui. |
| `captureNothingRead` | No encontré movimientos. Prueba con un monto, como «15 mil en almuerzo». | Non ho trovato movimenti. Prova con un importo, come «15 pranzo». | Não encontrei movimentos. Experimenta com um valor, como «15 almoço». |
| `captureOfferTitle` | Para escucharte, Wambito necesita su voz en español | Per ascoltarti, Wambito ha bisogno della sua voce in italiano | Para te ouvir, Wambito precisa da sua voz em português |
| `captureOfferBody` | Se descarga una sola vez ({megabytes} MB) y queda en tu teléfono: escucha sin internet y lo que dices nunca sale de él. Sin ella, puedes escribir. | Si scarica una sola volta ({megabytes} MB) e resta sul tuo telefono: ascolta senza internet e quello che dici non esce mai da lì. Senza la voce, puoi scrivere. | Descarrega-se uma só vez ({megabytes} MB) e fica no teu telemóvel: ouve sem internet e o que dizes nunca sai de lá. Sem ela, podes escrever. |
| `captureDownloadFailed` | No se pudo descargar la voz. Revisa tu internet e inténtalo de nuevo; seguirá donde quedó. | Non è stato possibile scaricare la voce. Controlla internet e riprova: riprenderà da dove si era fermata. | Não foi possível descarregar a voz. Verifica a tua internet e tenta de novo; continua de onde parou. |
| `captureSaved` | ¡Listo! {count, plural, =1{1 movimiento} other{{count} movimientos}} por {amount} | Fatto! {count, plural, =1{1 movimento} other{{count} movimenti}} per {amount} | Pronto! {count, plural, =0{{count} movimentos} =1{1 movimento} other{{count} movimentos}} por {amount} |

### Guest accounts and saving progress

| key | es | it | pt |
|---|---|---|---|
| `guestSaveTitle` | ¿Guardamos lo que ya anotaste? | Salviamo quello che hai già annotato? | Guardamos o que já registaste? |
| `guestSaveBody` | Estás usando Wambito sin correo. Podemos guardar tu progreso en {email}: sigues con los mismos movimientos. | Stai usando Wambito senza email. Possiamo salvare i tuoi progressi in {email}: continui con gli stessi movimenti. | Estás a usar Wambito sem email. Podemos guardar o teu progresso em {email}: continuas com os mesmos movimentos. |
| `progressLead` | Sin correo, si pierdes el teléfono o borras la app, pierdes tus datos. | Senza email, se perdi il telefono o cancelli l'app, perdi i tuoi dati. | Sem email, se perderes o telemóvel ou apagares a app, perdes os teus dados. |
| `progressPasskeyBody` | Una huella en este teléfono te deja entrar sin correo, pero si pierdes el teléfono o la huella, pierdes la cuenta. Para usar Wambito en otro dispositivo o con asistentes de IA necesitas un correo. | Un'impronta su questo telefono ti fa entrare senza email, ma se perdi il telefono o l'impronta, perdi l'account. Per usare Wambito su un altro dispositivo o con gli assistenti IA ti serve un'email. | Uma impressão digital neste telemóvel deixa-te entrar sem email, mas se perderes o telemóvel ou a impressão digital, perdes a conta. Para usar Wambito noutro dispositivo ou com assistentes de IA precisas de um email. |

### Voice and model settings

| key | es | it | pt |
|---|---|---|---|
| `settingsDeleteVoice` | Borrar los modelos de voz | Elimina i modelli vocali | Apagar os modelos de voz |
| `settingsDeleteVoiceBody` | No podrás dictar hasta descargarlos de nuevo. Lo que ya anotaste no cambia. | Non potrai dettare finché non li scarichi di nuovo. Quello che hai già annotato non cambia. | Não poderás ditar até os descarregares de novo. O que já registaste não muda. |
| `settingsServerLead` | Otro servidor es otra cuenta: al cambiar, cierras sesión aquí. | Un altro server è un altro account: se lo cambi, esci da qui. | Outro servidor é outra conta: ao mudares, terminas a sessão aqui. |
| `settingsHideAmount` | Ocultar el monto | Nascondi l'importo | Ocultar o valor |

### Widget, tile and notices

| key | es | it | pt |
|---|---|---|---|
| `widget_remaining` | Te quedan | Ti restano | Restam-te |
| `widget_over` | Te pasaste | Hai sforato | Passaste do limite |
| `widget_remaining_past` | Te quedaron en %1$s | Ti sono rimasti in %1$s | Sobraram-te em %1$s |
| `widget_signed_out` | Abre Wambito para empezar | Apri Wambito per iniziare | Abre Wambito para começar |
| `widget_stale` | hace un rato | poco fa | há algum tempo |
| `tile_capture` | Decir un gasto | Annota una spesa | Registar uma despesa |
| `widget_small_description` | Lo que te queda este mes, y ＋ para anotar un gasto. | Quello che ti resta questo mese, e ＋ per annotare una spesa. | O que te resta este mês, e ＋ para registar uma despesa. |
| `notice_due_one` | Hoy vence %1$s | Oggi scade %1$s | Hoje vence %1$s |
| `notice_due_many` | Hoy vencen %1$s | Oggi scadono %1$s | Hoje vencem %1$s |
| `notice_guest` | Tus datos se borrarán en 15 días si no agregas tu correo | I tuoi dati verranno cancellati tra 15 giorni se non aggiungi la tua email | Os teus dados serão apagados dentro de 15 dias se não adicionares o teu email |
| `noticeAskDue` | Así Wambito puede avisarte a las 9:00 los días en que vence un pago recurrente. | Così Wambito può avvisarti alle 9:00 nei giorni in cui scade un pagamento ricorrente. | Assim Wambito pode avisar-te às 9:00 nos dias em que vence um pagamento recorrente. |

### Store

| key | es | it | pt |
|---|---|---|---|
| `short_description.txt` | Anota un gasto en segundos, con tu voz si quieres. Libre y sin rastreadores. | Annota una spesa in pochi secondi. Libera e senza tracker. | Regista uma despesa em segundos. Livre e sem rastreadores. |
