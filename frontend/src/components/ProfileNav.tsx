"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { COGNITO_DOMAIN, COGNITO_CLIENT_ID, REDIRECT_URI } from "@/config/auth";

const links = [
  { href: "/", label: "Home" }
];

/* ---------- PKCE helpers (browser only) ---------- */
const b64url = (buf: ArrayBuffer) =>
  btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");

const createVerifier = () => {
  const bytes = new Uint8Array(64);
  crypto.getRandomValues(bytes);
  return b64url(bytes.buffer); // ~86 chars, valid for PKCE (43–128)
};

const createChallenge = async (verifier: string) => {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier)
  );
  return b64url(digest);
};

const createState = () => {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return b64url(bytes.buffer);
};

export default function ProfileNav() {
  const pathname = usePathname();
  const [busy, setBusy] = React.useState(false);

  const handleSignIn = React.useCallback(async () => {
    try {
      if (!("crypto" in window) || !("subtle" in crypto)) {
        throw new Error("Web Crypto API unavailable (need HTTPS).");
      }

      setBusy(true);

      const verifier = createVerifier();
      const challenge = await createChallenge(verifier);
      const state = createState();

      // Persist for the callback page
      sessionStorage.setItem("pkce_verifier", verifier);
      sessionStorage.setItem("oauth_state", state);

      const domain = COGNITO_DOMAIN.replace(/\/+$/, "");
      const url = new URL(`${domain}/oauth2/authorize`);
      url.searchParams.set("client_id", COGNITO_CLIENT_ID);
      url.searchParams.set("response_type", "code");
      url.searchParams.set("redirect_uri", REDIRECT_URI);
      url.searchParams.set("scope", "openid email profile");
      url.searchParams.set("code_challenge_method", "S256");
      url.searchParams.set("code_challenge", challenge);
      url.searchParams.set("state", state);

      window.location.assign(url.toString());
    } catch (e) {
      console.error(e);
      setBusy(false);
      // Optionally show a toast/UI message
    }
  }, []);

  return (
    <aside className="sticky top-8 self-start">
      <div className="flex items-center gap-4">
        <div>
          <h1 className="text-2xl font-bold leading-6">Serverless cognito cloudfront signed cookie auth infrastructure</h1>
        </div>
      </div>

      <nav className="mt-4 grid gap-2">
        {links.map((l) => {
          const active = pathname === l.href;
          return (
            <Link
              key={l.href}
              href={l.href}
              className={[
                "rounded-lg border px-3 py-2 text-sm transition-colors",
                active
                  ? "border-amber-300 bg-amber-50 text-zinc-900"
                  : "border-zinc-200 hover:bg-zinc-50",
              ].join(" ")}
            >
              {l.label}
            </Link>
          );
        })}
      </nav>

      <div className="mt-4">
        <button
          type="button"
          onClick={handleSignIn}
          disabled={busy}
          aria-busy={busy || undefined}
          className="w-full rounded-lg bg-amber-500 px-3 py-2 text-sm font-medium text-white hover:bg-amber-600 disabled:opacity-60"
        >
          {busy ? "Redirecting…" : "Sign in"}
        </button>
      </div>
    </aside>
  );
}
