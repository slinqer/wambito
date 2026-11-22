import type { Meta, StoryObj } from "@storybook/react-vite";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { expectTarget } from "../../../.storybook/story-utils.ts";
import type { PasskeyOfferApi } from "./PasskeyOffer.tsx";
import {
  fakeAuth,
  fakeOffer,
  GOOD_CODE,
  NEW_USER,
  ONBOARDED_USER,
  SignInStage,
} from "./story-harness.tsx";

const meta = {
  title: "Sign-in/PasskeyOffer",
  component: SignInStage,
  args: {
    auth: fakeAuth({ shouldOfferPasskey: fn(async () => true) }),
    offer: fakeOffer(),
    initialEntry: "/passkey-offer?next=%2Fwelcome",
  },
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

/** The offer: what a passkey is, in plain words, and two ways out. The heading has the focus. */
export const Offer: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const heading = canvas.getByRole("heading", {
      level: 1,
      name: "¿Entrar con tu huella la próxima vez?",
    });
    await waitFor(() => expect(heading).toHaveFocus());
    const points = within(canvas.getByRole("list"));
    await expect(points.getAllByRole("listitem")).toHaveLength(4);
    await expect(
      points.getByText(
        "Una passkey es una llave guardada en este teléfono, en Google, Samsung Pass, iCloud o Proton Pass.",
      ),
    ).toBeVisible();
    await expect(
      points.getByText("Tu huella o tu cara solo la desbloquean. Wambito nunca las recibe."),
    ).toBeVisible();
    await expect(
      points.getByText("Se sincroniza con tus otros dispositivos que usan la misma cuenta."),
    ).toBeVisible();
    await expect(points.getByText("Tu correo sigue funcionando como respaldo.")).toBeVisible();
    await expectTarget(canvas.getByRole("button", { name: "Crear mi huella" }));
    await expectTarget(canvas.getByRole("button", { name: "Ahora no" }));
  },
};

/** The same offer in English, by day (contrast is checked in both themes). */
export const OfferDayEnglish: Story = {
  globals: { theme: "day", locale: "en" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { level: 1, name: "Sign in with your fingerprint next time?" }),
    ).toBeVisible();
    await expect(
      canvas.getByText(
        "A passkey is a key saved on this phone, in Google, Samsung Pass, iCloud or Proton Pass.",
      ),
    ).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Create my fingerprint" })).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Not now" })).toBeVisible();
  },
};

/** "Ahora no" is remembered for this user and goes on to where sign-in was heading. */
export const NotNow: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Ahora no" }));
    await expect(args.offer?.add).not.toHaveBeenCalled();
    await expect(args.offer?.decide).toHaveBeenCalledWith(NEW_USER.id);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
  },
};

/** "Crear mi huella" creates the passkey, confirms with a toast, remembers and goes on. */
export const CreatePasskey: Story = {
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const page = within(canvasElement.ownerDocument.body);
    await userEvent.click(canvas.getByRole("button", { name: "Crear mi huella" }));
    await expect(args.offer?.add).toHaveBeenCalledTimes(1);
    await expect(args.offer?.decide).toHaveBeenCalledWith(NEW_USER.id);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
    const toast = await page.findByText("Listo: la próxima vez entras con tu huella.");
    // The toast fades in (Motion): checked once it is fully opaque.
    await waitFor(() =>
      expect(getComputedStyle(toast.closest(".lk-toast") ?? toast).opacity).toBe("1"),
    );
  },
};

/**
 * An encrypted account whose new passkey gives its PRF: kept for the vault, so it goes on as
 * usual, with the toast.
 */
export const CreatePasskeyThatUnlocks: Story = {
  args: {
    offerEncrypted: true,
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Crear mi huella" }));
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
    await expect(args.offer?.decide).toHaveBeenCalledWith(NEW_USER.id);
    const toast = await within(canvasElement.ownerDocument.body).findByText(
      "Listo: la próxima vez entras con tu huella.",
    );
    // The toast fades in (Motion): checked once it is fully opaque.
    await waitFor(() =>
      expect(getComputedStyle(toast.closest(".lk-toast") ?? toast).opacity).toBe("1"),
    );
  },
};

/**
 * An encrypted account whose new passkey gives no PRF (Proton Pass, 1Password): the passkey is
 * kept, and the screen says at once, as text that stays (not a toast), that it signs in but does
 * not open the data; "Seguir" goes on.
 */
export const CreatePasskeyWithoutPrf: Story = {
  args: {
    offerEncrypted: true,
    offer: fakeOffer({
      add: fn(async (hooks?: Parameters<PasskeyOfferApi["add"]>[0]) => {
        hooks?.onNoPrf?.();
        return "added" as const;
      }),
    }),
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Crear mi huella" }));
    const notice = await canvas.findByText(
      "Esta huella sirve para entrar, pero tu gestor de contraseñas no le permite abrir tus datos. Guarda tu clave de recuperación: la vas a necesitar en un dispositivo nuevo.",
    );
    await expect(notice).toHaveAttribute("role", "status");
    await expect(notice.closest(".lk-toast")).toBeNull();
    await expect(args.offer?.decide).toHaveBeenCalledWith(NEW_USER.id);
    await expect(currentPage(canvas)).toHaveTextContent("/passkey-offer");
    await expect(canvas.queryByRole("button", { name: "Crear mi huella" })).toBeNull();
    const go = canvas.getByRole("button", { name: "Seguir" });
    await expectTarget(go);
    await userEvent.click(go);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
  },
};

/**
 * An encrypted account whose new passkey's second touch was cancelled (or failed): nothing was
 * kept, but the password manager is not the cause, so no notice: it goes on as usual.
 */
export const CreatePasskeySecondTouchCancelled: Story = {
  args: { offerEncrypted: true },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Crear mi huella" }));
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
    await expect(args.offer?.decide).toHaveBeenCalledWith(NEW_USER.id);
    await expect(canvas.queryByText(/no le permite abrir tus datos/)).toBeNull();
    const toast = await within(canvasElement.ownerDocument.body).findByText(
      "Listo: la próxima vez entras con tu huella.",
    );
    // The toast fades in (Motion): checked once it is fully opaque.
    await waitFor(() =>
      expect(getComputedStyle(toast.closest(".lk-toast") ?? toast).opacity).toBe("1"),
    );
  },
};

/** The browser's prompt is open: the buttons wait, and say so. */
export const WaitingForTheFingerprint: Story = {
  args: { offer: fakeOffer({ add: fn(() => new Promise<never>(() => {})) }) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Crear mi huella" }));
    await expect(
      await canvas.findByRole("button", { name: "Esperando tu huella…" }),
    ).toBeDisabled();
    await expect(canvas.getByRole("button", { name: "Ahora no" })).toBeDisabled();
  },
};

/** Closing the browser's prompt is a choice, not an error: nothing is announced, and it can be retried. */
export const Cancelled: Story = {
  args: { offer: fakeOffer({ add: fn(async () => "cancelled" as const) }) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    const create = canvas.getByRole("button", { name: "Crear mi huella" });
    await userEvent.click(create);
    await expect(args.offer?.add).toHaveBeenCalled();
    await waitFor(() => expect(create).toBeEnabled());
    await expect(canvas.queryByRole("alert")).toBeNull();
    await expect(args.offer?.decide).not.toHaveBeenCalled();
    await expect(canvas.getByRole("heading", { level: 1 })).toBeVisible();
  },
};

/** A passkey that could not be saved says so, and "Ahora no" is still there. */
export const Failed: Story = {
  args: { offer: fakeOffer({ add: fn(async () => "failed" as const) }) },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Crear mi huella" }));
    await expect(await canvas.findByRole("alert")).toHaveTextContent(
      "No pudimos guardar tu huella. Inténtalo otra vez o sigue sin ella.",
    );
    await expect(args.offer?.decide).not.toHaveBeenCalled();
    await expect(canvas.getByRole("button", { name: "Ahora no" })).toBeEnabled();
  },
};

/** Where WebAuthn doesn't exist there is nothing to offer: straight on. */
export const Unsupported: Story = {
  args: { offer: fakeOffer({ supported: () => false }) },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
    await expect(canvas.queryByRole("heading", { name: /huella/ })).toBeNull();
  },
};

/** A `next` that leaves the site is ignored. */
export const UnsafeNext: Story = {
  args: { initialEntry: "/passkey-offer?next=https%3A%2F%2Fevil.example" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Ahora no" }));
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/app"));
  },
};

/** The first email sign-in of a new user: the offer comes before onboarding, then onboarding. */
export const AfterTheFirstSignIn: Story = {
  args: {
    auth: fakeAuth({ shouldOfferPasskey: fn(async () => true) }),
    initialEntry: AT_CODE_STEP,
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.type(digits(canvas)[0] as HTMLElement, GOOD_CODE);
    const heading = await canvas.findByRole("heading", {
      level: 1,
      name: "¿Entrar con tu huella la próxima vez?",
    });
    await expect(args.auth.shouldOfferPasskey).toHaveBeenCalledWith(NEW_USER.id);
    await waitFor(() => expect(heading).toHaveFocus());
    await expect(currentPage(canvas)).toHaveTextContent("/passkey-offer");
    await userEvent.click(canvas.getByRole("button", { name: "Ahora no" }));
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
  },
};

/** A returning user with no passkey yet gets the offer too, and then goes to the app. */
export const ReturningUserWithoutAPasskey: Story = {
  args: {
    auth: fakeAuth({ shouldOfferPasskey: fn(async () => true), user: ONBOARDED_USER }),
    initialEntry: { ...AT_CODE_STEP, search: "?lang=es&next=%2Fapp%2Finsights" },
    profileUser: ONBOARDED_USER,
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.type(digits(canvas)[0] as HTMLElement, GOOD_CODE);
    await canvas.findByRole("heading", { level: 1, name: "¿Entrar con tu huella la próxima vez?" });
    await expect(args.auth.shouldOfferPasskey).toHaveBeenCalledWith(ONBOARDED_USER.id);
    await userEvent.click(canvas.getByRole("button", { name: "Crear mi huella" }));
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/app/insights"));
    const toast = await within(canvasElement.ownerDocument.body).findByText(
      "Listo: la próxima vez entras con tu huella.",
    );
    await waitFor(() =>
      expect(getComputedStyle(toast.closest(".lk-toast") ?? toast).opacity).toBe("1"),
    );
  },
};

/** When no offer is due (answered before, a passkey exists, no WebAuthn) sign-in goes straight on. */
export const NoOfferDue: Story = {
  args: {
    auth: fakeAuth({ shouldOfferPasskey: fn(async () => false) }),
    initialEntry: AT_CODE_STEP,
  },
  play: async ({ canvasElement, args }) => {
    const canvas = within(canvasElement);
    await userEvent.type(digits(canvas)[0] as HTMLElement, GOOD_CODE);
    await waitFor(() => expect(currentPage(canvas)).toHaveTextContent("/welcome"));
    await expect(args.auth.shouldOfferPasskey).toHaveBeenCalledWith(NEW_USER.id);
  },
};
