import { encryptedStoreContract } from "./encrypted-contract.ts";
import { createMemoryEncryptedStore } from "./memory-encrypted-store.ts";
import { storeContract } from "./store-contract.ts";

storeContract("memory encrypted store", () => createMemoryEncryptedStore("u1"));
encryptedStoreContract("memory encrypted store", () => createMemoryEncryptedStore("u1"));
