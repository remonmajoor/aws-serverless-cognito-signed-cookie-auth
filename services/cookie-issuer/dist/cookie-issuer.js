"use strict";
/// <reference types="node" />
/// <reference types="aws-lambda" />
Object.defineProperty(exports, "__esModule", { value: true });
exports.handler = void 0;
exports.getSigningKey = getSigningKey;
const node_crypto_1 = require("node:crypto");
const client_secrets_manager_1 = require("@aws-sdk/client-secrets-manager");
/*Env config (fail fast if missing)*/
const AWS_REGION = mustEnv("AWS_REGION");
const USER_POOL_ID = mustEnv("COG_USER_POOL_ID");
const APP_CLIENT_ID = mustEnv("COG_APP_CLIENT_ID");
const CF_COOKIE_DOMAIN = mustEnv("CF_COOKIE_DOMAIN");
const CF_KEY_PAIR_ID = mustEnv("CF_KEY_PAIR_ID");
const PRIVATE_KEY_ARN = mustEnv("PRIVATE_KEY_ARN");
const CF_RESOURCE = process.env.CF_RESOURCE || "/restricted/*";
const COOKIE_TTL_SECONDS = intFromEnv("COOKIE_TTL_SECONDS", 1800); // 30m default
function mustEnv(name) {
    const v = process.env[name];
    if (!v)
        throw new Error(`Missing env var: ${name}`);
    return v;
}
function intFromEnv(name, dflt) {
    const raw = process.env[name];
    const n = raw ? parseInt(raw, 10) : dflt;
    return Number.isFinite(n) ? n : dflt;
}
/** --------- Simple in-memory JWKS cache --------- */
let jwksByKid = null;
let jwksFetchedAt = 0;
const client = new client_secrets_manager_1.SecretsManagerClient({}); // reused across warm invokes
const TTL_MS = 5 * 60 * 1000;
let cached;
async function fetchJWKS() {
    const url = `https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}/.well-known/jwks.json`;
    const res = await fetch(url);
    if (!res.ok)
        throw new Error(`JWKS fetch failed: ${res.status}`);
    const body = (await res.json());
    jwksByKid = Object.fromEntries((body.keys || []).map((k) => [k.kid, k]));
    jwksFetchedAt = Date.now();
}
async function getSigningKey(force = false) {
    // Use cache on warm invocations
    if (!force && cached && Date.now() - cached.ts < TTL_MS) {
        return cached.value;
    }
    const response = await client.send(new client_secrets_manager_1.GetSecretValueCommand({
        SecretId: PRIVATE_KEY_ARN,
        VersionStage: "AWSCURRENT", // always the current version
    }));
    const raw = response.SecretString ?? Buffer.from(response.SecretBinary).toString("utf8");
    const value = JSON.parse(raw);
    cached = { value, ts: Date.now(), versionId: response.VersionId };
    return value;
}
function parseJwt(token) {
    const [h, p, s] = token.split(".");
    if (!h || !p || !s)
        throw new Error("Malformed JWT");
    const header = JSON.parse(Buffer.from(h, "base64url").toString("utf8"));
    const payload = JSON.parse(Buffer.from(p, "base64url").toString("utf8"));
    const signature = Buffer.from(s, "base64url");
    return { header, payload, signature, signingInput: `${h}.${p}` };
}
async function verifyJwtCognito(idOrAccessToken) {
    const { header, payload, signature, signingInput } = parseJwt(idOrAccessToken);
    if (header.alg !== "RS256")
        throw new Error("Unsupported alg");
    const needRefresh = !jwksByKid || Date.now() - jwksFetchedAt > 12 * 3600 * 1000 || !(header.kid in jwksByKid);
    if (needRefresh)
        await fetchJWKS();
    const jwk = jwksByKid?.[header.kid];
    if (!jwk)
        throw new Error("Unknown kid in JWT");
    const nodeJwk = {
        kty: "RSA",
        n: jwk.n,
        e: jwk.e,
        kid: jwk.kid,
        alg: "RS256",
        use: "sig",
    };
    const publicKey = (0, node_crypto_1.createPublicKey)({ key: nodeJwk, format: "jwk" });
    const valid = (0, node_crypto_1.verify)("RSA-SHA256", Buffer.from(signingInput), publicKey, signature);
    if (!valid)
        throw new Error("Bad signature");
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && now >= payload.exp)
        throw new Error("Token expired");
    if (payload.nbf && now < payload.nbf)
        throw new Error("Token not yet valid");
    const expectedIss = `https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}`;
    if (payload.iss !== expectedIss)
        throw new Error("Bad iss");
    const tokenUse = payload.token_use;
    const audienceOk = (tokenUse === "id" && payload.aud === APP_CLIENT_ID) ||
        (tokenUse === "access" && payload.client_id === APP_CLIENT_ID);
    if (!audienceOk)
        throw new Error("Bad audience/client_id");
    return payload;
}
/** --------- CloudFront cookie signing ---------
 * CloudFront expects a SHA1 RSA signature and a "cookie-safe" base64:
 *   '+' -> '-', '=' -> '_', '/' -> '~'
 */
const toCfBase64 = (input) => Buffer.from(input).toString("base64");
function cfEncode(b64) {
    return b64.replace(/\+/g, "-").replace(/=/g, "_").replace(/\//g, "~");
}
function signPolicy(privateKeyPem, policyJson) {
    const signer = (0, node_crypto_1.createSign)("RSA-SHA1"); // CloudFront requires SHA1 for signed cookies/URLs
    signer.update(policyJson);
    return signer.sign(privateKeyPem);
}
function buildPolicy(host) {
    const expiresEpoch = Math.floor(Date.now() / 1000) + COOKIE_TTL_SECONDS;
    const resource = `https://${host}${CF_RESOURCE.startsWith("/") ? "" : "/"}${CF_RESOURCE}`;
    const policy = {
        Statement: [
            {
                Resource: resource,
                Condition: {
                    DateLessThan: { "AWS:EpochTime": expiresEpoch },
                },
            },
        ],
    };
    return { policyJson: JSON.stringify(policy), expiresEpoch };
}
async function makeSetCookieHeaders() {
    const { policyJson } = buildPolicy(CF_COOKIE_DOMAIN);
    const privateKey = await getSigningKey();
    const privateKeyPEM = privateKey.privateKeyPem;
    const signature = signPolicy(privateKeyPEM, policyJson);
    const cookies = {
        "CloudFront-Policy": cfEncode(toCfBase64(policyJson)),
        "CloudFront-Signature": cfEncode(toCfBase64(signature)),
        "CloudFront-Key-Pair-Id": CF_KEY_PAIR_ID,
    };
    // Important: cookies must be set on the CloudFront host
    const attrs = `Path=/; Domain=${CF_COOKIE_DOMAIN}; Secure; HttpOnly; SameSite=Lax; Max-Age=${COOKIE_TTL_SECONDS}`;
    return Object.entries(cookies).map(([k, v]) => `${k}=${v}; ${attrs}`);
}
const handler = async (event) => {
    const headers = event.headers || {};
    const authHeader = headers.authorization || headers["Authorization"] || "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : undefined;
    if (!token) {
        return { statusCode: 401, body: "Missing Bearer token" };
    }
    try {
        await verifyJwtCognito(token);
        const setCookies = await makeSetCookieHeaders();
        return {
            statusCode: 204,
            headers: { "cache-control": "no-store" },
            cookies: setCookies,
        };
    }
    catch {
        return { statusCode: 403, body: "Forbidden" };
    }
};
exports.handler = handler;
