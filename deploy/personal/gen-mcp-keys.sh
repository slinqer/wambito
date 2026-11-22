#!/usr/bin/env bash
# Prints a fresh key pair for the MCP, as the two lines to paste into .env: MCP_WK_PUBLIC_KEY (the
# API's, no private part) and MCP_WK_PRIVATE_KEY (the MCP's). Each is a JWK as a JSON string
# (X25519, for ECDH-ES). The API seals the assistant secret of an encrypted account to the public
# key (the access token's `wk` claim); only the MCP holds the private one. Make the pair once.
# Losing the private key, or replacing the pair, disconnects every assistant on an encrypted
# account: each one must connect again (plain accounts are not touched). The output is a secret:
# do not paste it anywhere but .env. Needs node and the repository's dependencies (pnpm install);
# jose is the API's. Run: ./gen-mcp-keys.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# jose lives in apps/api's node_modules (pnpm does not hoist it): run from there so it resolves.
cd "$here/../../apps/api"
[ -d node_modules/jose ] || {
  echo "error: jose is not installed: run pnpm install in the repository first" >&2
  exit 1
}
exec node --input-type=module -e '
import { exportJWK, generateKeyPair } from "jose";
const pair = await generateKeyPair("ECDH-ES", { crv: "X25519", extractable: true });
const line = async (name, key) => `${name}=\x27${JSON.stringify(await exportJWK(key))}\x27`;
console.log(await line("MCP_WK_PUBLIC_KEY", pair.publicKey));
console.log(await line("MCP_WK_PRIVATE_KEY", pair.privateKey));
'
