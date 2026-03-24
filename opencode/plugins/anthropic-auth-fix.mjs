#!/usr/bin/env bun
/**
 * Workaround for opencode-anthropic-auth plugin failing to save OAuth tokens.
 * Tries to refresh existing tokens first; falls back to the full browser OAuth flow.
 *
 * Usage: bun plugins/anthropic-auth-fix.mjs
 */
import * as crypto from "crypto";
import * as readline from "readline";
import { readFileSync, writeFileSync } from "fs";
import { join } from "path";

function generatePKCE() {
  const verifier = crypto.randomBytes(32).toString("base64url");
  const challenge = crypto
    .createHash("sha256")
    .update(verifier)
    .digest("base64url");
  return { verifier, challenge };
}

const CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e";
const AUTH_PATH = join(
  process.env.HOME,
  ".local/share/opencode/auth.json",
);

function saveTokens(auth, json) {
  auth.anthropic = {
    type: "oauth",
    refresh: json.refresh_token,
    access: json.access_token,
    expires: Date.now() + json.expires_in * 1000,
  };
  writeFileSync(AUTH_PATH, JSON.stringify(auth, null, 2) + "\n");
  console.log(`\nTokens saved to ${AUTH_PATH}`);
  console.log(`Access token expires in ${json.expires_in / 3600} hours`);
}

// 1. Try to refresh existing token
let auth = {};
try {
  auth = JSON.parse(readFileSync(AUTH_PATH, "utf-8"));
} catch {
  // file doesn't exist or is invalid, start fresh
}

if (auth.anthropic?.refresh) {
  console.log("Attempting token refresh...");
  const refreshResult = await fetch(
    "https://console.anthropic.com/v1/oauth/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        grant_type: "refresh_token",
        refresh_token: auth.anthropic.refresh,
        client_id: CLIENT_ID,
      }),
    },
  );

  if (refreshResult.ok) {
    const json = await refreshResult.json();
    saveTokens(auth, json);
    console.log("Token refreshed successfully.");
    process.exit(0);
  }

  console.log(
    `Refresh failed (${refreshResult.status}), falling back to browser flow...\n`,
  );
}

// 2. Full browser OAuth flow
const pkce = generatePKCE();
const url = new URL("https://claude.ai/oauth/authorize");
url.searchParams.set("code", "true");
url.searchParams.set("client_id", CLIENT_ID);
url.searchParams.set("response_type", "code");
url.searchParams.set(
  "redirect_uri",
  "https://console.anthropic.com/oauth/code/callback",
);
url.searchParams.set(
  "scope",
  "org:create_api_key user:profile user:inference",
);
url.searchParams.set("code_challenge", pkce.challenge);
url.searchParams.set("code_challenge_method", "S256");
url.searchParams.set("state", pkce.verifier);

console.log("1. Open this URL in your browser:\n");
console.log(url.toString());
console.log("\n2. Paste the authorization code below:\n");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});
const code = await new Promise((resolve) => rl.question("> ", resolve));
rl.close();

const splits = code.trim().split("#");
const result = await fetch(
  "https://console.anthropic.com/v1/oauth/token",
  {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      code: splits[0],
      state: splits[1],
      grant_type: "authorization_code",
      client_id: CLIENT_ID,
      redirect_uri:
        "https://console.anthropic.com/oauth/code/callback",
      code_verifier: pkce.verifier,
    }),
  },
);

if (!result.ok) {
  const text = await result.text();
  console.error(`\nToken exchange failed (${result.status}):`);
  console.error(text);
  process.exit(1);
}

const json = await result.json();
saveTokens(auth, json);
console.log(`Account: ${json.account?.email_address ?? "unknown"}`);
