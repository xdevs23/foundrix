interface DesiredState {
  stalwartUrl: string;
  adminPasswordPath: string;
  // Address domains — the part after the @ in a mailbox. NOT the mail
  // hostnames: those carry TLS and the web UI and never appear in an address.
  // The first is the reporting domain (DMARC/TLS reports, ARC seal).
  domains: string[];
  publicUrl: string;
}

interface Principal {
  id: number;
  name: string;
  type: string;
  emails?: string[];
  description?: string;
}

class StalwartClient {
  private auth: string;

  constructor(
    private baseUrl: string,
    adminPassword: string,
  ) {
    this.auth = btoa(`admin:${adminPassword}`);
  }

  private async request(
    method: string,
    path: string,
    body?: unknown,
  ): Promise<{ ok: boolean; status: number; data: unknown }> {
    const resp = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Basic ${this.auth}`,
        "Content-Type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
    });

    const text = await resp.text();
    let data: unknown = null;
    try {
      const json = JSON.parse(text);
      data = json.data ?? json;
    } catch {
      data = text;
    }

    return { ok: resp.ok, status: resp.status, data };
  }

  async isReady(): Promise<boolean> {
    try {
      const resp = await fetch(
        `${this.baseUrl}/api/settings/list?prefix=server.hostname`,
        {
          headers: { Authorization: `Basic ${this.auth}` },
          signal: AbortSignal.timeout(5000),
        },
      );
      return resp.ok;
    } catch {
      return false;
    }
  }

  async getPrincipal(name: string): Promise<Principal | null> {
    const { ok, data } = await this.request(
      "GET",
      `/api/principal/${encodeURIComponent(name)}`,
    );
    if (!ok) return null;
    return data as Principal;
  }

  async deployPrincipal(principal: Record<string, unknown>): Promise<void> {
    const { ok, data } = await this.request(
      "POST",
      "/api/principal/deploy",
      principal,
    );
    if (!ok) {
      throw new Error(`Failed to deploy principal: ${JSON.stringify(data)}`);
    }
  }

  async updatePrincipal(
    name: string,
    updates: Array<{ action: string; field: string; value: unknown }>,
  ): Promise<void> {
    const { ok, data } = await this.request(
      "PATCH",
      `/api/principal/${encodeURIComponent(name)}`,
      updates,
    );
    if (!ok) {
      throw new Error(`Failed to update principal: ${JSON.stringify(data)}`);
    }
  }

  async getSettings(prefix: string): Promise<Record<string, string>> {
    const { ok, data } = await this.request(
      "GET",
      `/api/settings/list?prefix=${encodeURIComponent(prefix)}`,
    );
    if (!ok) throw new Error(`Failed to list settings: ${JSON.stringify(data)}`);
    return ((data as { items: Record<string, string> }).items) ?? {};
  }

  async setSettings(values: Array<[string, string]>): Promise<void> {
    const { ok, data } = await this.request("POST", "/api/settings", [
      { type: "insert", prefix: null, values, assert_empty: false },
    ]);
    if (!ok) throw new Error(`Failed to set settings: ${JSON.stringify(data)}`);
  }

  async reload(): Promise<void> {
    const { ok, data } = await this.request("GET", "/api/reload");
    if (!ok) throw new Error(`Failed to reload config: ${JSON.stringify(data)}`);
  }

  async createDkim(body: {
    algorithm: string;
    domain: string;
    selector?: string;
  }): Promise<void> {
    const { ok, data } = await this.request("POST", "/api/dkim", body);
    if (!ok) throw new Error(`Failed to create DKIM signature: ${JSON.stringify(data)}`);
  }

  async getDkimPublicKey(signatureId: string): Promise<string | null> {
    const { ok, data } = await this.request(
      "GET",
      `/api/dkim/${encodeURIComponent(signatureId)}`,
    );
    if (!ok) return null;
    return data as string;
  }

  async clearSettings(prefix: string): Promise<void> {
    const { ok, data } = await this.request("POST", "/api/settings", [
      { type: "clear", prefix },
    ]);
    if (!ok) throw new Error(`Failed to clear settings: ${JSON.stringify(data)}`);
  }
}

async function waitForApi(client: StalwartClient): Promise<void> {
  for (;;) {
    if (await client.isReady()) {
      console.log("Stalwart API is ready");
      return;
    }
    console.log("Stalwart not ready, retrying in 2s...");
    await new Promise((r) => setTimeout(r, 2000));
  }
}

function convergeDomain(
  client: StalwartClient,
  domain: string,
): Promise<void> {
  console.log(`Deploying domain: ${domain}`);
  return client.deployPrincipal({ type: "domain", name: domain });
}

async function convergeDkimSignature(
  client: StalwartClient,
  algorithm: "Ed25519" | "Rsa",
  domain: string,
  selector: string,
): Promise<void> {
  const sigId = `${algorithm.toLowerCase()}-${domain}`;

  const existing = await client.getSettings(`signature.${sigId}`);
  if (Object.keys(existing).length > 0) {
    console.log(`DKIM signature '${sigId}' already configured`);
    return;
  }

  console.log(`Creating ${algorithm} DKIM signature '${sigId}'...`);
  await client.createDkim({ algorithm, domain, selector });

  const publicKey = await client.getDkimPublicKey(sigId);
  const keyType = algorithm === "Ed25519" ? "ed25519" : "rsa";
  if (publicKey) {
    console.log(
      `\n  DNS record:\n  ${selector}._domainkey.${domain} TXT "v=DKIM1; k=${keyType}; p=${publicKey}"\n`,
    );
  }
}

async function convergeDkim(
  client: StalwartClient,
  domain: string,
): Promise<void> {
  await convergeDkimSignature(client, "Rsa", domain, "rsa");
  await convergeDkimSignature(client, "Ed25519", domain, "ed");
}

// One global setting, not a per-domain one: it names the two signatures of the
// reporting domain and Stalwart resolves `report.domain` at send time. Hence it
// converges once, after every domain's signatures exist — putting it inside the
// per-domain loop would rewrite the same value N times.
async function convergeArcSeal(client: StalwartClient): Promise<void> {
  const desiredArcSeal = `['rsa-' + config_get('report.domain'), 'ed25519-' + config_get('report.domain')]`;
  const arcSeal = await client.getSettings("auth.arc.seal");
  if (arcSeal["auth.arc.seal"] !== desiredArcSeal) {
    console.log("Configuring ARC sealing with both RSA and Ed25519...");
    await client.clearSettings("auth.arc.seal");
    await client.setSettings([["auth.arc.seal", desiredArcSeal]]);
  }
}

async function convergeAdminAccount(
  client: StalwartClient,
  domains: string[],
): Promise<void> {
  const desiredEmails = domains.flatMap((domain) => [
    `admin@${domain}`,
    `postmaster@${domain}`,
    `webmaster@${domain}`,
    `@${domain}`,
  ]);

  const admin = await client.getPrincipal("admin");

  if (!admin) {
    console.log("Deploying admin account");
    await client.deployPrincipal({
      type: "individual",
      name: "admin",
      emails: desiredEmails,
      description: "System administrator",
    });
    console.log("Admin account deployed");
    return;
  }

  console.log(`Admin account exists (emails: ${(admin.emails ?? []).join(", ")})`);

  const missing = desiredEmails.filter((e) => !(admin.emails ?? []).includes(e));
  if (missing.length > 0) {
    console.log(`Adding missing aliases: ${missing.join(", ")}`);
    await client.updatePrincipal(
      "admin",
      missing.map((e) => ({ action: "addItem", field: "emails", value: e })),
    );
  } else {
    console.log("Admin account already converged");
  }
}

async function convergeSettings(client: StalwartClient, domain: string, publicUrl: string): Promise<void> {
  const desired: Record<string, string> = {
    "session.mta-sts.mode": "enforce",
    "report.domain": domain,
    "http.url": publicUrl,
  };

  for (const [key, value] of Object.entries(desired)) {
    const current = await client.getSettings(key);
    if (current[key] !== value) {
      console.log(`Setting ${key} = ${value}`);
      await client.clearSettings(key);
      await client.setSettings([[key, value]]);
    }
  }
}

async function main(): Promise<void> {
  const specPath = Deno.args[0];
  if (!specPath) {
    console.error("Usage: stalwart-configure.ts <desired-state.json>");
    Deno.exit(1);
  }

  const spec: DesiredState = JSON.parse(await Deno.readTextFile(specPath));
  const adminPassword = (
    await Deno.readTextFile(spec.adminPasswordPath)
  ).trim();
  const client = new StalwartClient(spec.stalwartUrl, adminPassword);

  await waitForApi(client);

  for (const domain of spec.domains) {
    await convergeDomain(client, domain);
    await convergeDkim(client, domain);
  }

  await convergeArcSeal(client);
  await convergeAdminAccount(client, spec.domains);
  await convergeSettings(client, spec.domains[0], spec.publicUrl);

  console.log("Reloading configuration...");
  await client.reload();

  console.log("Stalwart configuration complete");
}

main();
