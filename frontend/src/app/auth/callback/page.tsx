"use client";

import * as React from "react";
import {
  COGNITO_DOMAIN,
  COGNITO_CLIENT_ID,
  REDIRECT_URI,
} from "@/config/auth";

type TokenResponse = {
  id_token: string;
  access_token: string;
  refresh_token?: string;
  token_type: "Bearer";
  expires_in: number;
};

const toForm = (o: Record<string, string>) =>
  new URLSearchParams(o).toString();

export default function CallbackPage() {
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    (async () => {
      try {
        // 1) Read params & PKCE stash
        const qs = new URLSearchParams(window.location.search);
        const code = qs.get("code");
        const state = qs.get("state");
        const expectedState = sessionStorage.getItem("oauth_state") || "";
        const verifier = sessionStorage.getItem("pkce_verifier") || "";

        if (!code) throw new Error("Missing 'code' from Cognito.");
        if (!state || state !== expectedState)
          throw new Error("State mismatch.");
        if (!verifier) throw new Error("Missing PKCE verifier.");

        // 2) Exchange code → tokens (PKCE)
        const tokenRes = await fetch(
          `${COGNITO_DOMAIN.replace(/\/$/, "")}/oauth2/token`,
          {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: toForm({
              grant_type: "authorization_code",
              client_id: COGNITO_CLIENT_ID,
              code,
              redirect_uri: REDIRECT_URI, //this is an OAuth2 requirement, it's not a mistake
              code_verifier: verifier,
            }),
          }
        );
        if (!tokenRes.ok)
          throw new Error(`Token exchange failed (${tokenRes.status}).`);
        const tokens = (await tokenRes.json()) as TokenResponse;

        // 3) Ask your API (same CF host) to set CloudFront signed cookies
        const cookieRes = await fetch("/api/auth", {
          method: "POST",
          headers: { Authorization: `Bearer ${tokens.id_token}` },
          credentials: "include",
        });
        if (!cookieRes.ok && cookieRes.status !== 204)
          throw new Error(`Cookie mint failed (${cookieRes.status}).`);

        // 4) Cleanup and go home
        sessionStorage.removeItem("pkce_verifier");
        sessionStorage.removeItem("oauth_state");
        window.location.replace("/");
        } catch (err: unknown) {
            console.error(err);
            const message =
                err instanceof Error ? err.message : typeof err === "string" ? err : "Login error";
            setError(message as string);
        }
    })();
  }, []);

  return (
    <main className="mx-auto max-w-md py-12">
      <h1 className="text-xl font-semibold">Signing you in…</h1>
      <p className="text-sm text-zinc-600 mt-2">
        Exchanging the authorization code and setting secure cookies.
      </p>
      {error && (
        <p className="mt-4 rounded bg-red-50 p-3 text-sm text-red-700">
          {error}
        </p>
      )}
    </main>
  );
}
