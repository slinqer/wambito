import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import { detectLocale } from "../../i18n/format.ts";
import type { CodeHints } from "./auth.ts";
import {
  fail,
  fakeAuth,
  GOOD_CODE,
  liveQr,
  ONBOARDED_USER,
  ok,
  SignInStage,
} from "./story-harness.tsx";

const meta = {
  title: "Sign-in/SignIn",
  component: SignInStage,
  // `?lang=es` pins the language the screens send and set (it matches the fake profile's).
  args: { auth: fakeAuth(), initialEntry: "/sign-in?lang=es" },
} satisfies Meta<typeof SignInStage>;

export default meta;
type Story = StoryObj<typeof meta>;

const AT_CODE_STEP = {
  pathname: "/sign-in",
  search: "?lang=es",
  state: { email: "ana@example.com", codeSent: true },
};

const digits = (canvas: ReturnType<typeof within>) =>
  canvas.getAllByRole("textbox", { name: /^Dígito \d de 6$/ });

const currentPage = (canvas: ReturnType<typeof within>) =>
  canvas.getByRole("status", { name: "Current page" });

/** The email step: Wambi, the email field and "send code". No fingerprint button without WebAuthn. */
export const EmailStep: Story = {
  args: { auth: fakeAuth() },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Entra a Wambito" })).toBeVisible();
    await expect(canvas.getByRole("img", { name: "Wambi, contento" })).toBeVisible();
    const email = canvas.getByRole("textbox", { name: "Tu correo" });
    await expect(email).toHaveAttribute("type", "email");
    // Its name comes from a real, visible label, never from the placeholder.
    const label = (email as HTMLInputElement).labels?.[0];
    await expect(label).toHaveTextContent("Tu correo");
    await expect(label).toBeVisible();
    await expect(email).not.toHaveAttribute("placeholder", "Tu correo");
    // Existing passkeys appear in the field's autofill (WebAuthn conditional mediation).
    await expect(email).toHaveAttribute("autocomplete", "username webauthn");
    const send = canvas.getByRole("button", { name: "Enviar código" });
    await expectTarget(send);
    await expect(canvas.queryByRole("button", { name: "Entrar con huella" })).toBeNull();
    // Without WebAuthn there is nothing to ask the browser for.
    await expect(args.auth.autofillPasskey).not.toHaveBeenCalled();
    // A newcomer is told how it works, under the form.
    await expect(
      canvas.getByText("¿Primera vez? Entra con tu correo; después podrás usar tu huella."),
    ).toBeVisible();
  },
};

/** Typing an email and sending the code moves to the code step: 6 boxes, the first ready for autofill. */
export const EmailToCode: Story = {
  args: { auth: fakeAuth() },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.type(canvas.getByRole("textbox", { name: "Tu correo" }), " Ana@Example.com ");
    await userEvent.click(canvas.getByRole("button", { name: "Enviar código" }));
    // The API writes the email (and its link) in the page's language.
    await expect(args.auth.sendCode).toHaveBeenCalledWith("ana@example.com", {
      locale: "es",
      next: null,
    });
    await expect(
      await canvas.findByRole("heading", { level: 1, name: "Revisa tu correo" }),
    ).toBeVisible();
    await expect(canvas.getByText("ana@example.com")).toBeVisible();
    const boxes = digits(canvas);
    await expect(boxes).toHaveLength(6);
    await expect(boxes[0]).toHaveAttribute("autocomplete", "one-time-code");
    await expect(boxes[0]).toHaveAttribute("inputmode", "numeric");
    await waitFor(() => expect(boxes[0]).toHaveFocus());
    await expect(canvas.getByRole("group", { name: "Código de 6 dígitos" })).toBeVisible();
    // "Resend" waits 30 s after a code was sent.
    const wait = canvas.getByRole("button", { name: /^Reenviar en \d+ s$/ });
    await expect(wait).toBeDisabled();
    await expect(Number(/\d+/.exec(wait.textContent ?? "")?.[0])).toBeGreaterThan(25);
    for (const box of boxes) await expectTarget(box);
  },
};

/** A malformed email never reaches the server: the field says what is wrong. */
export const InvalidEmail: Story = {
  args: { auth: fakeAuth() },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const email = canvas.getByRole("textbox", { name: "Tu correo" });
    await userEvent.type(email, "ana@");
    await userEvent.click(canvas.getByRole("button", { name: "Enviar código" }));
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Escribe un correo válido, como ana@correo.com.",
    );
    await expect(email).toHaveAttribute("aria-invalid", "true");
    await expect(email).toHaveFocus();
    await expect(args.auth.sendCode).not.toHaveBeenCalled();
  },
};

/** Too many codes requested: the rate limit's message, and the email step stays. */
export const TooManyCodes: Story = {
  args: {
    auth: fakeAuth({ sendCode: fn(async () => fail({ status: 429 })) }),
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.type(canvas.getByRole("textbox", { name: "Tu correo" }), "ana@example.com");
    await userEvent.click(canvas.getByRole("button", { name: "Enviar código" }));
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Pediste muchos códigos seguidos. Espera unos minutos e inténtalo otra vez.",
    );
    await expect(canvas.getByRole("heading", { level: 1, name: "Entra a Wambito" })).toBeVisible();
  },
};

/** A wrong code: the error is announced, the boxes are marked invalid and emptied for another try. */
export const WrongCode: Story = {
  args: { auth: fakeAuth(), initialEntry: AT_CODE_STEP },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const boxes = digits(canvas);
    await userEvent.type(boxes[0] as HTMLElement, "123456");
    await expect(args.auth.verifyCode).toHaveBeenCalledWith("ana@example.com", "123456", {
      locale: "es",
    });
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Ese código no es correcto. Revísalo e inténtalo otra vez.",
    );
    for (const box of digits(canvas)) {
      await expect(box).toHaveAttribute("aria-invalid", "true");
      await expect(box).toHaveValue("");
    }
    await waitFor(() => expect(digits(canvas)[0]).toHaveFocus());
    await expect(currentPage(canvas)).toHaveTextContent("/sign-in");
  },
};

/** The same error by day (contrast is checked in both themes). */
export const WrongCodeDay: Story = {
  ...WrongCode,
  globals: { theme: "day" },
};

/** An expired code says so (a code lasts 10 minutes). */
export const ExpiredCode: Story = {
  args: {
    auth: fakeAuth({ verifyCode: fn(async () => fail({ code: "OTP_EXPIRED", status: 400 })) }),
    initialEntry: AT_CODE_STEP,
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.type(digits(canvas)[0] as HTMLElement, "123456");
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Este código ya no sirve: venció o ya se usó. Pide uno nuevo.",
    );
  },
};

/** The right code signs a new user in and takes them to onboarding. */
export const RightCode: Story = {
  args: { auth: fakeAuth(), initialEntry: AT_CODE_STEP, onPatchMe: fn() },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.type(digits(canvas)[0] as HTMLElement, GOOD_CODE);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
    // `?lang=es` is already the profile's language: nothing to change.
    await expect(args.onPatchMe).not.toHaveBeenCalled();
    // The passkey offer was considered for this user, and not needed here.
    await expect(args.auth.shouldOfferPasskey).toHaveBeenCalledWith("u-new");
  },
};

/** A whole code pasted into the first box fills all six and signs in. */
export const PasteCode: Story = {
  args: { auth: fakeAuth(), initialEntry: AT_CODE_STEP },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(digits(canvas)[0] as HTMLElement);
    await userEvent.paste("42 42 42");
    await expect(args.auth.verifyCode).toHaveBeenCalledWith("ana@example.com", GOOD_CODE, {
      locale: "es",
    });
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
  },
};

/** Came from the English landing (`?lang=en`): a new user's profile is set to English. */
export const NewUserFromEnglishLanding: Story = {
  args: {
    auth: fakeAuth(),
    initialEntry: { ...AT_CODE_STEP, search: "?lang=en" },
    onPatchMe: fn(),
  },
  globals: { locale: "en" },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Check your email" })).toBeVisible();
    const boxes = canvas.getAllByRole("textbox", { name: /^Digit \d of 6$/ });
    await userEvent.type(boxes[0] as HTMLElement, GOOD_CODE);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
    await expect(args.onPatchMe).toHaveBeenCalledWith({ locale: "en" });
  },
};

/** "Resend" unlocks after the wait (shortened here), sends again and confirms with a toast. */
export const Resend: Story = {
  args: { auth: fakeAuth(), initialEntry: AT_CODE_STEP, resendDelayMs: 1000 },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const page = within(canvasElement.ownerDocument.body);
    const resend = await canvas.findByRole(
      "button",
      { name: "Reenviar código" },
      { timeout: 5000 },
    );
    await expect(resend).toBeEnabled();
    await userEvent.click(resend);
    await expect(args.auth.sendCode).toHaveBeenCalledWith(
      "ana@example.com",
      expect.objectContaining({ locale: "es" }),
    );
    const toast = await page.findByText("Te mandamos un código nuevo.");
    // The toast fades in (Motion): give it time on a loaded machine.
    await waitFor(() => expect(toast).toBeVisible());
    await expect(canvas.getByRole("button", { name: /^Reenviar en \d+ s$/ })).toBeDisabled();
  },
};

/** "Use another email" goes back to the email step with the address filled in. */
export const ChangeEmail: Story = {
  args: { auth: fakeAuth(), initialEntry: AT_CODE_STEP },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Usar otro correo" }));
    await expect(canvas.getByRole("textbox", { name: "Tu correo" })).toHaveValue("ana@example.com");
  },
};

/**
 * A browser that has used a passkey before: "Sign in with fingerprint" comes first; a passkey
 * sign-in goes on to `next`, and is never followed by the offer to create one.
 */
export const Passkey: Story = {
  args: {
    auth: fakeAuth({
      passkeysAvailable: () => true,
      passkeyUsedHere: () => true,
      user: ONBOARDED_USER,
    }),
    initialEntry: "/sign-in?lang=es&next=%2Fapp%2Finsights",
    profileUser: ONBOARDED_USER,
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const passkey = canvas.getByRole("button", { name: "Entrar con huella" });
    await expectTarget(passkey);
    const send = canvas.getByRole("button", { name: "Enviar código" });
    // "Shown first": the fingerprint button comes before the email form.
    await expect(
      passkey.compareDocumentPosition(send) & Node.DOCUMENT_POSITION_FOLLOWING,
    ).toBeTruthy();
    await userEvent.click(passkey);
    await expect(args.auth.signInWithPasskey).toHaveBeenCalled();
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/app/insights"));
    await expect(args.auth.shouldOfferPasskey).not.toHaveBeenCalled();
  },
};

/**
 * WebAuthn is there but this browser has never used a passkey: no fingerprint button (the OS would
 * only say "no sign-in available"). The browser is still asked quietly, for the email field's
 * autofill.
 */
export const NoFingerprintButtonYet: Story = {
  args: { auth: fakeAuth({ passkeysAvailable: () => true, passkeyUsedHere: () => false }) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Entra a Wambito" })).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Entrar con huella" })).toBeNull();
    // the line still parts the recovery key from the email form
    await expect(canvas.getByText("o con tu correo")).toBeVisible();
    await expect(canvas.getByRole("textbox", { name: "Tu correo" })).toHaveAttribute(
      "autocomplete",
      "username webauthn",
    );
    await waitFor(() => expect(args.auth.autofillPasskey).toHaveBeenCalledTimes(1));
    await expect(canvas.getByRole("button", { name: "Enviar código" })).toBeEnabled();
  },
};

/** Once a passkey has signed in or been registered here, the fingerprint button shows. */
export const FingerprintButtonAfterAPasskey: Story = {
  args: { auth: fakeAuth({ passkeysAvailable: () => true, passkeyUsedHere: () => true }) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Entrar con huella" })).toBeVisible();
    await expect(canvas.getByText("o con tu correo")).toBeVisible();
    await waitFor(() => expect(args.auth.autofillPasskey).toHaveBeenCalledTimes(1));
  },
};

/** Picking a passkey from the email field's autofill signs in, with no button pressed. */
export const PasskeyFromAutofill: Story = {
  args: {
    auth: fakeAuth({
      passkeysAvailable: () => true,
      autofillPasskey: fn(async () => ok(ONBOARDED_USER)),
      user: ONBOARDED_USER,
    }),
    initialEntry: "/sign-in?lang=es&next=%2Fapp%2Finsights",
    profileUser: ONBOARDED_USER,
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/app/insights"));
    await expect(args.auth.shouldOfferPasskey).not.toHaveBeenCalled();
  },
};

/** The autofill request ending without a choice (closed, aborted, unsupported) says nothing. */
export const AutofillStaysQuiet: Story = {
  args: {
    auth: fakeAuth({
      passkeysAvailable: () => true,
      autofillPasskey: fn(async () => fail({ code: "ERROR_CEREMONY_ABORTED", status: 400 })),
    }),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await waitFor(() => expect(args.auth.autofillPasskey).toHaveBeenCalled());
    await expect(canvas.queryByRole("alert")).toBeNull();
    await expect(canvas.getByRole("button", { name: "Enviar código" })).toBeEnabled();
  },
};

/** A passkey sign-in that fails explains itself and leaves the email route open. */
export const PasskeyFailed: Story = {
  args: {
    auth: fakeAuth({
      passkeysAvailable: () => true,
      passkeyUsedHere: () => true,
      signInWithPasskey: fn(async () => fail({ code: "PASSKEY_NOT_FOUND", status: 400 })),
    }),
    initialEntry: "/sign-in?lang=en",
  },
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Sign in with fingerprint" }));
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "We couldn't sign you in with your fingerprint. Try again or use your email.",
    );
    await expect(canvas.getByRole("textbox", { name: "Your email" })).toBeEnabled();
  },
};

/** The verify call is in flight: the button says so and can't be pressed twice. */
export const CheckingCode: Story = {
  args: {
    auth: fakeAuth({ verifyCode: fn(() => new Promise<never>(() => {})) }),
    initialEntry: AT_CODE_STEP,
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.type(digits(canvas)[0] as HTMLElement, "123456");
    await expect(await canvas.findByRole("button", { name: "Entrando…" })).toBeDisabled();
  },
};

/** Closing the browser's passkey prompt is a choice, not an error: nothing is announced. */
export const PasskeyCancelled: Story = {
  args: {
    auth: fakeAuth({
      passkeysAvailable: () => true,
      passkeyUsedHere: () => true,
      signInWithPasskey: fn(async () => fail({ code: "AUTH_CANCELLED", status: 400 })),
    }),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const passkey = canvas.getByRole("button", { name: "Entrar con huella" });
    await userEvent.click(passkey);
    await expect(args.auth.signInWithPasskey).toHaveBeenCalled();
    await waitFor(() => expect(passkey).toBeEnabled());
    await expect(canvas.queryByRole("alert")).toBeNull();
  },
};

/** No connection while checking: the message, and the typed code stays for another try. */
export const OfflineKeepsCode: Story = {
  args: {
    auth: fakeAuth({ verifyCode: fn(async () => fail({ status: 0 })) }),
    initialEntry: AT_CODE_STEP,
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.type(digits(canvas)[0] as HTMLElement, "123456");
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Sin conexión. Revisa tu internet e inténtalo de nuevo.",
    );
    await expect(
      digits(canvas)
        .map((box: HTMLElement) => (box as HTMLInputElement).value)
        .join(""),
    ).toBe("123456");
    for (const box of digits(canvas)) await expect(box).not.toHaveAttribute("aria-invalid");
    await expect(canvas.getByRole("button", { name: "Entrar" })).toBeEnabled();
  },
};

/** The first check is rate limited (retry after 2 s); the next one goes through. */
const rateLimitedOnce = fn(async (email: string, code: string, hints: CodeHints) =>
  rateLimitedOnce.mock.calls.length === 1
    ? fail({ status: 429, retryAfter: 2 })
    : fakeAuth().verifyCode(email, code, hints),
);

/** Too many sign-ins in a row: wait the seconds the server asked for, then the same code works. */
export const SignInRateLimited: Story = {
  args: {
    auth: fakeAuth({ verifyCode: rateLimitedOnce }),
    initialEntry: AT_CODE_STEP,
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.type(digits(canvas)[0] as HTMLElement, GOOD_CODE);
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Demasiados intentos seguidos. Espera unos segundos e inténtalo otra vez.",
    );
    await expect(canvas.getByRole("button", { name: /^Espera \d s$/ })).toBeDisabled();
    const retry = await canvas.findByRole("button", { name: "Entrar" }, { timeout: 5000 });
    await userEvent.click(retry);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
    await expect(args.auth.verifyCode).toHaveBeenCalledTimes(2);
  },
};

/** A resend that fails says why, without marking the typed code as wrong. */
export const ResendFails: Story = {
  args: {
    auth: fakeAuth({ sendCode: fn(async () => fail({ status: 429 })) }),
    initialEntry: AT_CODE_STEP,
    resendDelayMs: 0,
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Reenviar código" }));
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Pediste muchos códigos seguidos. Espera unos minutos e inténtalo otra vez.",
    );
    for (const box of digits(canvas)) await expect(box).not.toHaveAttribute("aria-invalid");
  },
};

/** No `?lang=`: the browser's language is the one the email (and a new profile) gets. */
export const BrowserLanguage: Story = {
  args: { auth: fakeAuth(), initialEntry: "/sign-in" },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.type(canvas.getByRole("textbox", { name: "Tu correo" }), "ana@example.com");
    await userEvent.click(canvas.getByRole("button", { name: "Enviar código" }));
    await expect(args.auth.sendCode).toHaveBeenCalledWith("ana@example.com", {
      locale: detectLocale(navigator.language),
      next: null,
    });
  },
};

/** The screen as wide as a computer's (the layout reads the screen's width, ruling 12). */
const atWidth = (width: number) => (Story: () => React.ReactNode) => (
  <div style={{ width }}>
    <Story />
  </div>
);

const topOf = (element: Element) => element.getBoundingClientRect().top;
const leftOf = (element: Element) => element.getBoundingClientRect().left;

/**
 * `/sign-in` on a computer: the QR panel for the phone first, its box ticked, then "Other ways to
 * sign in" with the email form, both on the page.
 */
export const PhoneFirst: Story = {
  name: "Phone first",
  decorators: [atWidth(1024)],
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Entra a Wambito" })).toBeVisible();
    const qr = await canvas.findByRole("img", { name: "ABCDEFGH" });
    await expect(qr).toBeVisible();
    await expect(
      canvas.getByRole("checkbox", { name: "Mantener la sesión abierta en este navegador" }),
    ).toBeChecked();
    const email = canvas.getByRole("textbox", { name: "Tu correo" });
    await expect(email).toBeVisible();
    await expect(canvas.getByRole("heading", { name: "Otras formas de entrar" })).toBeVisible();
    // the QR comes first: beside the other ways, on their left
    await expect(leftOf(qr)).toBeLessThan(leftOf(email));
    await expect(canvas.getByRole("button", { name: "Más opciones" })).toBeVisible();
  },
};

/**
 * The recovery key waits under "More options" (closed by default); opening shows its field at
 * once; a key the server does not know reads `recovery_key_invalid`.
 */
export const RecoveryKey: Story = {
  name: "Recovery key",
  args: {
    auth: fakeAuth({
      signInWithRecoveryKey: fn(async (_text: string) => ({
        error: "recovery_key_invalid" as const,
      })),
    }),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const open = canvas.getByRole("button", { name: "Más opciones" });
    await expect(open).toHaveAttribute("aria-expanded", "false");
    await expect(canvas.queryByRole("textbox", { name: "Tu clave de recuperación" })).toBeNull();
    await expect(canvas.queryByRole("button", { name: "Clave de recuperación" })).toBeNull();
    await userEvent.click(open);
    const field = await canvas.findByRole("textbox", { name: "Tu clave de recuperación" });
    await expect(field).toHaveFocus();
    await expect(open).toHaveAttribute("aria-expanded", "true");
    const submit = canvas.getByRole("button", { name: "Entrar con la clave" });
    // The field groups what is typed; the button waits for the whole key.
    await userEvent.type(field, "abcd efgh jkmn pqrs tvwx yz01 23");
    await expect(field).toHaveValue("ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-23");
    await expect(submit).toBeDisabled();
    await userEvent.type(field, "4");
    await expect(field).toHaveValue("ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-234");
    await expect(submit).toBeEnabled();
    await userEvent.click(submit);
    await expect(args.auth.signInWithRecoveryKey).toHaveBeenCalledWith(
      "ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-234",
    );
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "Esta clave de recuperación no inicia sesión. Revísala e inténtalo de nuevo.",
    );
    await expect(field).toHaveAttribute("aria-invalid", "true");
    await expect(currentPage(canvas)).toHaveTextContent("/sign-in");
  },
};

/** A recovery key that signs in lands in the app; never the passkey offer. */
export const RecoveryKeySignsIn: Story = {
  name: "Recovery key signs in",
  args: {
    auth: fakeAuth({
      signInWithRecoveryKey: fn(async (_text: string) => ({ userId: ONBOARDED_USER.id })),
      shouldOfferPasskey: fn(async () => true),
    }),
    profileUser: ONBOARDED_USER,
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Más opciones" }));
    await userEvent.type(
      await canvas.findByRole("textbox", { name: "Tu clave de recuperación" }),
      "ABCD-EFGH-JKMN-PQRS-TVWX-YZ01-234",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Entrar con la clave" }));
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/app"));
    await expect(args.auth.shouldOfferPasskey).not.toHaveBeenCalled();
  },
};

/** `/create-account`: the email code form under "Create your account"; no QR, no other ways. */
export const CreateAccount: Story = {
  name: "Create account",
  args: { initialEntry: "/create-account?lang=es", qr: fn(() => liveQr()) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Crea tu cuenta" })).toBeVisible();
    await expect(canvas.getByRole("textbox", { name: "Tu correo" })).toBeVisible();
    await expect(canvas.queryByRole("img", { name: "ABCDEFGH" })).toBeNull();
    await expect(canvas.queryByRole("button", { name: "Más opciones" })).toBeNull();
    await expect(args.qr).not.toHaveBeenCalled();
    await expect(canvas.getByRole("link", { name: "Entra" })).toHaveAttribute(
      "href",
      "/sign-in?lang=es",
    );
  },
};

/** A phone: the other ways come first; the QR follows, for signing in on a computer. */
export const Phone: Story = {
  name: "Phone",
  decorators: [atWidth(375)],
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const email = canvas.getByRole("textbox", { name: "Tu correo" });
    const onComputer = canvas.getByText("¿Entras en un computador? Escanéalo con tu celular.");
    await expect(topOf(email)).toBeLessThan(topOf(onComputer));
    // the QR's request opens once the panel is on screen
    onComputer.scrollIntoView();
    const qrTitle = await canvas.findByRole("heading", { name: "Entra con tu celular" });
    await expect(topOf(email)).toBeLessThan(topOf(qrTitle));
    await expect(await canvas.findByRole("img", { name: "ABCDEFGH" })).toBeVisible();
  },
};

/** `/create-account` asks the browser for no passkey: it is for someone who has none yet. */
export const CreateAccountNoAutofill: Story = {
  name: "Create account, no passkey autofill",
  args: {
    initialEntry: "/create-account?lang=es",
    auth: fakeAuth({ passkeysAvailable: () => true, passkeyUsedHere: () => true }),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("heading", { level: 1, name: "Crea tu cuenta" })).toBeVisible();
    await expect(canvas.getByRole("textbox", { name: "Tu correo" })).toBeVisible();
    await new Promise((resolve) => setTimeout(resolve, 100));
    await expect(args.auth.autofillPasskey).not.toHaveBeenCalled();
    await expect(canvas.queryByRole("button", { name: "Entrar con huella" })).toBeNull();
  },
};
