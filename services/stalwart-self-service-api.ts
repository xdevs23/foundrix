// Privileged backend for the self-service page's address management.
//
// Aliases live on Stalwart principals, and changing them is a management
// operation the browser can never be allowed to perform directly: the page
// only holds OIDC tokens, and Stalwart's OIDC directory knows nothing about
// roles, so any token it accepts is an ordinary user. The admin web UI is not
// an alternative — saving a principal there silently deletes every app
// password the account has (format mismatch between server and webadmin,
// fixed upstream only in 0.16).
//
// So this service holds the fallback-admin credential and exposes the two
// operations the page needs — list and add/remove an address — and nothing
// else. It PATCHes only the `emails` field, which makes it structurally
// incapable of touching secrets.
//
// Authorization is the same gate as the page's admin section: the caller's
// bearer token is presented to Zitadel's userinfo endpoint, and the roles
// claim must carry the admin role. The token proves who is asking; the
// fallback-admin credential this service holds is what acts.
import { StalwartClient } from "./stalwart-configure.ts";

interface Spec {
  stalwartUrl: string;
  issuer: string;
  adminRole: string;
  // Domains an address may use — org domains plus extra delivery domains.
  addressDomains: string[];
  port: number;
}

const ROLES_CLAIM = "urn:zitadel:iam:org:project:roles";

const specPath = Deno.args[0];
if (!specPath) {
  console.error("Usage: stalwart-self-service-api.ts <spec.json>");
  Deno.exit(1);
}
const spec: Spec = JSON.parse(await Deno.readTextFile(specPath));

const credentialsDir = Deno.env.get("CREDENTIALS_DIRECTORY");
if (!credentialsDir) {
  console.error("CREDENTIALS_DIRECTORY is not set; expected an admin-password credential");
  Deno.exit(1);
}
const adminPassword = (
  await Deno.readTextFile(`${credentialsDir}/admin-password`)
).trim();
const client = new StalwartClient(spec.stalwartUrl, adminPassword);

// Discovered lazily and kept: the issuer may not be reachable yet when this
// service starts, and a failed attempt must not poison later requests.
let userinfoEndpoint: string | null = null;
async function getUserinfoEndpoint(): Promise<string> {
  if (userinfoEndpoint === null) {
    const resp = await fetch(`${spec.issuer}/.well-known/openid-configuration`);
    if (!resp.ok) {
      throw new Error(`OIDC discovery failed: ${resp.status}`);
    }
    userinfoEndpoint = (await resp.json()).userinfo_endpoint;
  }
  return userinfoEndpoint!;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Returns the acting admin's login name, or a ready error response. The
// token in the Authorization header must belong to a Zitadel account holding
// the admin role — the same check the page uses to show its admin section.
async function authorize(req: Request): Promise<string | Response> {
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return json(401, { error: "Missing bearer token" });
  }

  let resp: Response;
  try {
    resp = await fetch(await getUserinfoEndpoint(), {
      headers: { Authorization: auth },
    });
  } catch (e) {
    return json(502, { error: `Could not reach the identity provider: ${e}` });
  }
  if (!resp.ok) {
    return json(401, { error: "The identity provider rejected the token" });
  }

  const claims = await resp.json();
  const roles = claims?.[ROLES_CLAIM] ?? {};
  if (!Object.hasOwn(roles, spec.adminRole)) {
    return json(403, { error: "Admin role required" });
  }
  return claims?.preferred_username ?? "unknown-admin";
}

// An address is `local@domain` or the bare `@domain` catch-all, at a domain
// this deployment delivers for. Anything else is refused — this endpoint
// must never become a way to claim addresses at foreign domains.
function validateAddress(raw: string): { address: string } | { error: string } {
  const address = raw.trim().toLowerCase();
  const match = address.match(/^([a-z0-9._%+-]*)@([a-z0-9.-]+)$/);
  if (!match) {
    return { error: `Not a valid address: ${raw}` };
  }
  if (!spec.addressDomains.includes(match[2])) {
    return {
      error: `${match[2]} is not an address domain of this deployment`,
    };
  }
  return { address };
}

async function handleGet(url: URL): Promise<Response> {
  const account = url.searchParams.get("account");
  if (!account) {
    return json(400, { error: "Missing account parameter" });
  }
  const principal = await client.getPrincipal(account);
  if (!principal) {
    return json(404, {
      error:
        `No mailbox principal for ${account} — it exists once the account has authenticated`,
    });
  }
  return json(200, { name: principal.name, emails: principal.emails ?? [] });
}

async function handlePost(req: Request, admin: string): Promise<Response> {
  let body: { account?: string; add?: string; remove?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Request body is not JSON" });
  }
  const { account, add, remove } = body;
  if (!account || (add === undefined) === (remove === undefined)) {
    return json(400, {
      error: "Expected an account and exactly one of add/remove",
    });
  }

  const principal = await client.getPrincipal(account);
  if (!principal) {
    return json(404, {
      error:
        `No mailbox principal for ${account} — it exists once the account has authenticated`,
    });
  }
  const emails = principal.emails ?? [];

  if (add !== undefined) {
    const result = validateAddress(add);
    if ("error" in result) return json(400, result);
    if (!emails.includes(result.address)) {
      console.log(`${admin}: adding ${result.address} to ${principal.name}`);
      await client.updatePrincipal(principal.name, [
        { action: "addItem", field: "emails", value: result.address },
      ]);
    }
  } else {
    const address = remove!.trim().toLowerCase();
    // The login-name address is the account's identity, not an alias: it is
    // what the directory keeps re-asserting and what a mail client logs in
    // with, so removing it here would only break auth until the next sync.
    if (address === principal.name.toLowerCase()) {
      return json(400, { error: "The login address cannot be removed" });
    }
    if (emails.includes(address)) {
      console.log(`${admin}: removing ${address} from ${principal.name}`);
      await client.updatePrincipal(principal.name, [
        { action: "removeItem", field: "emails", value: address },
      ]);
    }
  }

  const updated = await client.getPrincipal(principal.name);
  return json(200, {
    name: principal.name,
    emails: updated?.emails ?? [],
  });
}

Deno.serve(
  { hostname: "127.0.0.1", port: spec.port },
  async (req: Request): Promise<Response> => {
    const url = new URL(req.url);
    if (url.pathname !== "/self-service/api/aliases") {
      return json(404, { error: "Not found" });
    }

    const admin = await authorize(req);
    if (admin instanceof Response) return admin;

    try {
      if (req.method === "GET") return await handleGet(url);
      if (req.method === "POST") return await handlePost(req, admin);
      return json(405, { error: "Method not allowed" });
    } catch (e) {
      console.error(`${req.method} ${url.pathname}: ${e}`);
      return json(500, { error: `${e}` });
    }
  },
);
