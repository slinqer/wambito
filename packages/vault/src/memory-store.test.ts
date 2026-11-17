import { createMemoryStore } from "./memory-store.ts";
import { storeContract } from "./store-contract.ts";

storeContract("memory store", () => createMemoryStore());
