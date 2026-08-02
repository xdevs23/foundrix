interface PasswordComplexityPolicy {
  minLength: number;
  hasUppercase: boolean;
  hasLowercase: boolean;
  hasNumber: boolean;
  hasSymbol: boolean;
}

interface LabelPolicy {
  primaryColor: string;
  backgroundColor: string;
  warnColor: string;
  fontColor: string;
  primaryColorDark: string;
  backgroundColorDark: string;
  warnColorDark: string;
  fontColorDark: string;
  hideLoginNameSuffix: boolean;
  disableWatermark: boolean;
  themeMode: number;
  logoUrl: string | null;
  logoUrlDark: string | null;
  iconUrl: string | null;
  iconUrlDark: string | null;
  fontUrl: string | null;
}

interface SecretGeneratorConfig {
  length: number;
  expirySeconds: number;
  includeLowerLetters: boolean;
  includeUpperLetters: boolean;
  includeDigits: boolean;
  includeSymbols: boolean;
}

interface InstanceSettings {
  passwordComplexity: PasswordComplexityPolicy | null;
  branding: LabelPolicy | null;
  languages: {
    default: string | null;
    allowed: string[] | null;
  } | null;
  oidcSettings: {
    accessTokenLifetimeSeconds: number;
    idTokenLifetimeSeconds: number;
    refreshTokenExpirationSeconds: number;
    refreshTokenIdleExpirationSeconds: number;
  } | null;
  secretGenerators: Record<string, SecretGeneratorConfig> | null;
}

interface OrgSettings {
  passwordComplexity: PasswordComplexityPolicy | null;
  branding: LabelPolicy | null;
}

interface DesiredState {
  apiUrl: string;
  patPath: string;
  adminOrg: string;
  adminUsername: string;
  orgDomains: string[];
  users: { username: string; displayName: string; passwordPath: string }[];
  policies: {
    domainPolicy: {
      userLoginMustBeDomain: boolean;
      validateOrgDomains: boolean;
    };
    loginPolicy: {
      allowRegister: boolean;
      allowExternalIdp: boolean;
    };
    disallowPublicOrgRegistration: boolean;
    enableImpersonation: boolean;
  };
  privacyPolicyLink: string | null;
  instance: InstanceSettings | null;
  orgs: Record<string, OrgSettings> | null;
  projects: Record<string, ProjectSpec>;
  actions: Record<string, ActionSpec>;
  adminIamRoles: string[];
}

interface ProjectSpec {
  apps: Record<string, AppSpec>;
  roles: Record<string, { displayName: string }>;
  userGrants: Record<string, string[]>;
}

interface ActionTrigger {
  flowType: string;
  triggerType: string;
}

interface ActionSpec {
  script: string;
  triggers: ActionTrigger[];
  timeout: string;
  allowedToFail: boolean;
}

type AppSpec = ConfidentialAppSpec | PublicAppSpec;

interface ConfidentialAppSpec {
  type: "confidential";
  redirectUris: string[];
  outputPath: string;
  accessTokenType: "bearer" | "jwt";
  grantTypes: string[];
}

interface PublicAppSpec {
  type: "public";
  redirectUris: string[];
  postLogoutRedirectUris: string[];
  outputPath: string;
  accessTokenType: "bearer" | "jwt";
  grantTypes: string[];
}

interface OrgDomain {
  domainName: string;
  isVerified: boolean;
  isPrimary: boolean;
}

interface ZitadelUser {
  id: string;
  userName: string;
  human?: {
    email?: {
      email: string;
    };
  };
}

class ZitadelClient {
  constructor(
    private apiUrl: string,
    private token: string,
  ) {}

  private async request(
    method: string,
    path: string,
    body?: unknown,
    orgId?: string,
  ): Promise<unknown> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.token}`,
      "Content-Type": "application/json",
    };
    // Management-API calls operate on the token's org unless overridden;
    // needed to configure a freshly created org.
    if (orgId) headers["x-zitadel-orgid"] = orgId;
    const resp = await fetch(`${this.apiUrl}${path}`, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });

    const text = await resp.text();
    if (!resp.ok) {
      if (resp.status === 400 && text.includes('"code":9')) {
        console.log(`${method} ${path}: already up to date`);
        return text ? JSON.parse(text) : {};
      }
      throw new Error(`${method} ${path} → ${resp.status}: ${text}`);
    }
    return text ? JSON.parse(text) : {};
  }

  async listOrgDomains(orgId?: string): Promise<OrgDomain[]> {
    const resp = (await this.request(
      "POST",
      "/management/v1/orgs/me/domains/_search",
      {},
      orgId,
    )) as {
      result?: OrgDomain[];
    };
    return resp.result ?? [];
  }

  async addOrgDomain(domain: string, orgId?: string): Promise<void> {
    await this.request("POST", "/management/v1/orgs/me/domains", { domain }, orgId);
  }

  async setPrimaryOrgDomain(domain: string, orgId?: string): Promise<void> {
    await this.request(
      "POST",
      `/management/v1/orgs/me/domains/${domain}/_set_primary`,
      {},
      orgId,
    );
  }

  async createHumanUser(
    username: string,
    displayName: string,
    email: string,
    password: string,
  ): Promise<void> {
    await this.request("POST", "/management/v1/users/human", {
      userName: username,
      profile: { firstName: displayName, lastName: displayName, displayName },
      // Both of these are what keep the account out of "Initial" state: an
      // account is sent an initialization email if its address is unverified
      // OR no password is set. Nothing is going to click a confirmation link
      // for an account the deployment created for itself — and worse, that
      // mail is addressed to a mailbox that does not exist yet.
      //
      // The field is `initialPassword`; a plain `password` is ignored, which
      // leaves the account passwordless and therefore Initial.
      email: { email, isEmailVerified: true },
      initialPassword: password,
    });
  }

  async createOrg(name: string): Promise<string> {
    // AddOrg lives in the management API; POST /admin/v1/orgs does not
    // exist (admin v1 only offers the deprecated _setup combo).
    const resp = (await this.request("POST", "/management/v1/orgs", { name })) as {
      id: string;
    };
    return resp.id;
  }

  async listOrgs(): Promise<{ id: string; name: string; primaryDomain?: string }[]> {
    const resp = (await this.request("POST", "/admin/v1/orgs/_search", {})) as {
      result?: { id: string; name: string; primaryDomain?: string }[];
    };
    return resp.result ?? [];
  }

  async createProjectGrant(
    projectId: string,
    grantedOrgId: string,
    roleKeys: string[],
  ): Promise<void> {
    await this.request("POST", `/management/v1/projects/${projectId}/grants`, {
      grantedOrgId,
      roleKeys,
    });
  }

  async listProjectGrants(projectId: string): Promise<{ grantedOrgId: string }[]> {
    const resp = (await this.request("POST", `/management/v1/projects/${projectId}/grants/_search`, {})) as {
      result?: { grantedOrgId: string }[];
    };
    return resp.result ?? [];
  }

  async getDomainPolicy(): Promise<Record<string, unknown>> {
    const resp = (await this.request("GET", "/admin/v1/policies/domain")) as {
      policy: Record<string, unknown>;
    };
    return resp.policy;
  }

  async updateDomainPolicy(policy: Record<string, unknown>): Promise<void> {
    await this.request("PUT", "/admin/v1/policies/domain", policy);
  }

  async getSecurityPolicy(): Promise<Record<string, unknown>> {
    const resp = (await this.request("GET", "/admin/v1/policies/security")) as {
      policy?: Record<string, unknown>;
    };
    return resp.policy ?? {};
  }

  async updateSecurityPolicy(policy: Record<string, unknown>): Promise<void> {
    await this.request("PUT", "/admin/v1/policies/security", policy);
  }

  async searchIamMembers(): Promise<{ userId: string; roles: string[] }[]> {
    const resp = (await this.request("POST", "/admin/v1/members/_search", {
      query: { limit: 100 },
    })) as { result?: { userId: string; roles?: string[] }[] };
    return (resp.result ?? []).map((m) => ({ userId: m.userId, roles: m.roles ?? [] }));
  }

  async addIamMember(userId: string, roles: string[]): Promise<void> {
    await this.request("POST", "/admin/v1/members", { userId, roles });
  }

  async updateIamMember(userId: string, roles: string[]): Promise<void> {
    await this.request("PUT", `/admin/v1/members/${userId}`, { roles });
  }

  async getLoginPolicy(): Promise<Record<string, unknown>> {
    const resp = (await this.request("GET", "/admin/v1/policies/login")) as {
      policy: Record<string, unknown>;
    };
    return resp.policy;
  }

  async updateLoginPolicy(policy: Record<string, unknown>): Promise<void> {
    await this.request("PUT", "/admin/v1/policies/login", policy);
  }

  async searchProjects(name: string): Promise<{ id: string; name: string }[]> {
    const resp = (await this.request("POST", "/management/v1/projects/_search", {
      queries: [{ nameQuery: { name, method: "TEXT_QUERY_METHOD_EQUALS" } }],
    })) as { result?: { id: string; name: string }[] };
    return resp.result ?? [];
  }

  async createProject(name: string): Promise<string> {
    const resp = (await this.request("POST", "/management/v1/projects", {
      name,
      projectRoleAssertion: true,
    })) as { id: string };
    return resp.id;
  }

  async getProject(id: string): Promise<{ name: string; projectRoleAssertion?: boolean }> {
    const resp = (await this.request("GET", `/management/v1/projects/${id}`)) as {
      project: { name: string; projectRoleAssertion?: boolean };
    };
    return resp.project;
  }

  async updateProject(id: string, settings: { name: string; projectRoleAssertion: boolean }): Promise<void> {
    await this.request("PUT", `/management/v1/projects/${id}`, settings);
  }

  async searchApps(
    projectId: string,
    name: string,
  ): Promise<{
    id: string;
    name: string;
    oidcConfig?: {
      clientId: string;
      redirectUris?: string[];
      postLogoutRedirectUris?: string[];
      accessTokenType?: string;
    };
  }[]> {
    const resp = (await this.request(
      "POST",
      `/management/v1/projects/${projectId}/apps/_search`,
      { queries: [{ nameQuery: { name, method: "TEXT_QUERY_METHOD_EQUALS" } }] },
    )) as {
      result?: {
        id: string;
        name: string;
        oidcConfig?: {
          clientId: string;
          redirectUris?: string[];
          postLogoutRedirectUris?: string[];
          accessTokenType?: string;
        };
      }[];
    };
    return resp.result ?? [];
  }

  async createOIDCApp(
    projectId: string,
    app: {
      name: string;
      redirectUris: string[];
      postLogoutRedirectUris?: string[];
      responseTypes: string[];
      grantTypes: string[];
      appType: string;
      authMethodType: string;
      accessTokenRoleAssertion?: boolean;
      idTokenRoleAssertion?: boolean;
      accessTokenType?: string;
    },
  ): Promise<{ clientId: string; clientSecret: string }> {
    const resp = (await this.request(
      "POST",
      `/management/v1/projects/${projectId}/apps/oidc`,
      app,
    )) as { clientId: string; clientSecret: string };
    return { clientId: resp.clientId, clientSecret: resp.clientSecret };
  }

  async regenerateClientSecret(projectId: string, appId: string): Promise<string> {
    const resp = (await this.request(
      "POST",
      `/management/v1/projects/${projectId}/apps/${appId}/oidc_config/_generate_client_secret`,
      {},
    )) as { clientSecret: string };
    return resp.clientSecret;
  }

  async updateOIDCAppConfig(
    projectId: string,
    appId: string,
    config: {
      redirectUris: string[];
      postLogoutRedirectUris?: string[];
      responseTypes: string[];
      grantTypes: string[];
      appType: string;
      authMethodType: string;
      accessTokenRoleAssertion?: boolean;
      idTokenRoleAssertion?: boolean;
      accessTokenType?: string;
    },
  ): Promise<void> {
    await this.request(
      "PUT",
      `/management/v1/projects/${projectId}/apps/${appId}/oidc_config`,
      config,
    );
  }

  async searchUsers(): Promise<ZitadelUser[]> {
    const resp = (await this.request("POST", "/management/v1/users/_search", {})) as {
      result?: ZitadelUser[];
    };
    return resp.result ?? [];
  }

  async updateUserEmail(userId: string, email: string): Promise<void> {
    await this.request("POST", `/v2/users/${userId}/email`, {
      email,
      isVerified: true,
    });
  }

  async addProjectRole(projectId: string, roleKey: string, displayName: string): Promise<void> {
    await this.request("POST", `/management/v1/projects/${projectId}/roles`, {
      roleKey,
      displayName,
    });
  }

  async searchProjectRoles(projectId: string): Promise<{ key: string }[]> {
    const resp = (await this.request("POST", `/management/v1/projects/${projectId}/roles/_search`, {})) as {
      result?: { key: string }[];
    };
    return resp.result ?? [];
  }

  async searchUserGrants(userId: string, projectId: string): Promise<{ id: string; roleKeys: string[] }[]> {
    const resp = (await this.request("POST", "/management/v1/users/grants/_search", {
      queries: [
        { userIdQuery: { userId } },
        { projectIdQuery: { projectId } },
      ],
    })) as { result?: { id: string; roleKeys: string[] }[] };
    return resp.result ?? [];
  }

  async createUserGrant(userId: string, projectId: string, roleKeys: string[]): Promise<void> {
    await this.request("POST", `/management/v1/users/${userId}/grants`, {
      projectId,
      roleKeys,
    });
  }

  async updateUserGrant(userId: string, grantId: string, roleKeys: string[]): Promise<void> {
    await this.request("PUT", `/management/v1/users/${userId}/grants/${grantId}`, {
      roleKeys,
    });
  }

  async getPrivacyPolicy(): Promise<{ tosLink?: string; privacyLink?: string; helpLink?: string }> {
    const resp = (await this.request("GET", "/admin/v1/policies/privacy")) as {
      policy: { tosLink?: string; privacyLink?: string; helpLink?: string };
    };
    return resp.policy;
  }

  async updatePrivacyPolicy(policy: { tosLink?: string; privacyLink?: string; helpLink?: string }): Promise<void> {
    await this.request("PUT", "/admin/v1/policies/privacy", policy);
  }

  // Instance-level settings (admin API)

  async getPasswordComplexityPolicy(): Promise<Record<string, unknown>> {
    const resp = (await this.request("GET", "/admin/v1/policies/password/complexity")) as { policy: Record<string, unknown> };
    return resp.policy;
  }

  async updatePasswordComplexityPolicy(policy: PasswordComplexityPolicy): Promise<void> {
    await this.request("PUT", "/admin/v1/policies/password/complexity", {
      minLength: policy.minLength,
      hasUppercase: policy.hasUppercase,
      hasLowercase: policy.hasLowercase,
      hasNumber: policy.hasNumber,
      hasSymbol: policy.hasSymbol,
    });
  }

  async getLabelPolicy(): Promise<Record<string, unknown>> {
    const resp = (await this.request("GET", "/admin/v1/policies/label")) as { policy: Record<string, unknown> };
    return resp.policy;
  }

  async updateLabelPolicy(policy: LabelPolicy): Promise<void> {
    await this.request("PUT", "/admin/v1/policies/label", {
      primaryColor: policy.primaryColor,
      backgroundColor: policy.backgroundColor,
      warnColor: policy.warnColor,
      fontColor: policy.fontColor,
      primaryColorDark: policy.primaryColorDark,
      backgroundColorDark: policy.backgroundColorDark,
      warnColorDark: policy.warnColorDark,
      fontColorDark: policy.fontColorDark,
      hideLoginNameSuffix: policy.hideLoginNameSuffix,
      disableWatermark: policy.disableWatermark,
      themeMode: policy.themeMode,
    });
  }

  async activateLabelPolicy(): Promise<void> {
    await this.request("POST", "/admin/v1/policies/label/_activate", {});
  }

  async uploadAsset(path: string, filePath: string): Promise<void> {
    const data = await Deno.readFile(filePath);
    const ext = filePath.split(".").pop()?.toLowerCase() ?? "";
    const mimeTypes: Record<string, string> = {
      png: "image/png",
      jpg: "image/jpeg",
      jpeg: "image/jpeg",
      svg: "image/svg+xml",
      gif: "image/gif",
      webp: "image/webp",
      ttf: "font/ttf",
      otf: "font/otf",
      woff: "font/woff",
      woff2: "font/woff2",
    };
    const contentType = mimeTypes[ext] ?? "image/png";
    const filename = filePath.split("/").pop() ?? "logo";

    const form = new FormData();
    form.append("file", new File([data], filename, { type: contentType }));

    const resp = await fetch(`${this.apiUrl}${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.token}`,
      },
      body: form,
    });
    if (!resp.ok) {
      const text = await resp.text();
      throw new Error(`POST ${path} → ${resp.status}: ${text}`);
    }
  }

  async setDefaultLanguage(language: string): Promise<void> {
    await this.request("PUT", `/admin/v1/languages/default/${language}`, {});
  }

  async setRestrictions(body: Record<string, unknown>): Promise<void> {
    await this.request("PUT", "/admin/v1/restrictions", body);
  }

  async updateOIDCSettings(settings: {
    accessTokenLifetime: string;
    idTokenLifetime: string;
    refreshTokenExpiration: string;
    refreshTokenIdleExpiration: string;
  }): Promise<void> {
    await this.request("PUT", "/admin/v1/settings/oidc", settings);
  }

  async updateSecretGenerator(generatorType: string, config: SecretGeneratorConfig): Promise<void> {
    await this.request("PUT", `/admin/v1/secretgenerators/${generatorType}`, {
      generatorType,
      length: config.length,
      expiry: `${config.expirySeconds}s`,
      includeLowerLetters: config.includeLowerLetters,
      includeUpperLetters: config.includeUpperLetters,
      includeDigits: config.includeDigits,
      includeSymbols: config.includeSymbols,
    });
  }

  // Org-level settings (management API)

  async getOrgPasswordComplexityPolicy(): Promise<{ policy: Record<string, unknown> }> {
    const resp = (await this.request("GET", "/management/v1/policies/password/complexity")) as { policy: Record<string, unknown> };
    return { policy: resp.policy };
  }

  async addCustomPasswordComplexityPolicy(policy: PasswordComplexityPolicy): Promise<void> {
    await this.request("POST", "/management/v1/policies/password/complexity", {
      minLength: policy.minLength,
      hasUppercase: policy.hasUppercase,
      hasLowercase: policy.hasLowercase,
      hasNumber: policy.hasNumber,
      hasSymbol: policy.hasSymbol,
    });
  }

  async updateCustomPasswordComplexityPolicy(policy: PasswordComplexityPolicy): Promise<void> {
    await this.request("PUT", "/management/v1/policies/password/complexity", {
      minLength: policy.minLength,
      hasUppercase: policy.hasUppercase,
      hasLowercase: policy.hasLowercase,
      hasNumber: policy.hasNumber,
      hasSymbol: policy.hasSymbol,
    });
  }

  async getOrgLabelPolicy(): Promise<{ policy: Record<string, unknown> }> {
    const resp = (await this.request("GET", "/management/v1/policies/label")) as { policy: Record<string, unknown> };
    return { policy: resp.policy };
  }

  async addCustomLabelPolicy(policy: LabelPolicy): Promise<void> {
    await this.request("POST", "/management/v1/policies/label", {
      primaryColor: policy.primaryColor,
      backgroundColor: policy.backgroundColor,
      warnColor: policy.warnColor,
      fontColor: policy.fontColor,
      primaryColorDark: policy.primaryColorDark,
      backgroundColorDark: policy.backgroundColorDark,
      warnColorDark: policy.warnColorDark,
      fontColorDark: policy.fontColorDark,
      hideLoginNameSuffix: policy.hideLoginNameSuffix,
      disableWatermark: policy.disableWatermark,
      themeMode: policy.themeMode,
    });
  }

  async updateCustomLabelPolicy(policy: LabelPolicy): Promise<void> {
    await this.request("PUT", "/management/v1/policies/label", {
      primaryColor: policy.primaryColor,
      backgroundColor: policy.backgroundColor,
      warnColor: policy.warnColor,
      fontColor: policy.fontColor,
      primaryColorDark: policy.primaryColorDark,
      backgroundColorDark: policy.backgroundColorDark,
      warnColorDark: policy.warnColorDark,
      fontColorDark: policy.fontColorDark,
      hideLoginNameSuffix: policy.hideLoginNameSuffix,
      disableWatermark: policy.disableWatermark,
      themeMode: policy.themeMode,
    });
  }

  async activateCustomLabelPolicy(): Promise<void> {
    await this.request("POST", "/management/v1/policies/label/_activate", {});
  }

  // Actions v1 API

  async listActions(): Promise<{
    id: string;
    name: string;
    script: string;
    state: string;
    timeout: string;
    allowedToFail: boolean;
  }[]> {
    const resp = (await this.request("POST", "/management/v1/actions/_search", {})) as {
      result?: {
        id: string;
        name: string;
        script: string;
        state: string;
        timeout: string;
        allowedToFail: boolean;
      }[];
    };
    return resp.result ?? [];
  }

  async createAction(action: {
    name: string;
    script: string;
    timeout: string;
    allowedToFail: boolean;
  }): Promise<string> {
    const resp = (await this.request("POST", "/management/v1/actions", action)) as { id: string };
    return resp.id;
  }

  async updateAction(id: string, action: {
    name: string;
    script: string;
    timeout: string;
    allowedToFail: boolean;
  }): Promise<void> {
    await this.request("PUT", `/management/v1/actions/${id}`, action);
  }

  async getFlow(flowType: string): Promise<{
    triggerActions: {
      triggerType: { id: string };
      actions: { id: string; name: string }[];
    }[];
  }> {
    const resp = (await this.request("GET", `/management/v1/flows/${flowType}`)) as {
      flow?: {
        triggerActions?: {
          triggerType: { id: string };
          actions: { id: string; name: string }[];
        }[];
      };
    };
    return {
      triggerActions: resp.flow?.triggerActions ?? [],
    };
  }

  async setTriggerActions(flowType: string, triggerType: string, actionIds: string[]): Promise<void> {
    await this.request("POST", `/management/v1/flows/${flowType}/trigger/${triggerType}`, {
      actionIds,
    });
  }
}

function zitadelAccessTokenType(t: "bearer" | "jwt"): string {
  return t === "jwt" ? "OIDC_TOKEN_TYPE_JWT" : "OIDC_TOKEN_TYPE_BEARER";
}

const GRANT_TYPES: Record<string, string> = {
  "authorization-code": "OIDC_GRANT_TYPE_AUTHORIZATION_CODE",
  "implicit": "OIDC_GRANT_TYPE_IMPLICIT",
  "refresh-token": "OIDC_GRANT_TYPE_REFRESH_TOKEN",
  "device-code": "OIDC_GRANT_TYPE_DEVICE_CODE",
  "token-exchange": "OIDC_GRANT_TYPE_TOKEN_EXCHANGE",
};

function zitadelGrantTypes(names: string[]): string[] {
  return names.map((name) => {
    const value = GRANT_TYPES[name];
    if (!value) throw new Error(`Unknown grant type: ${name}`);
    return value;
  });
}

async function waitForApi(client: ZitadelClient): Promise<void> {
  for (;;) {
    try {
      await client.listOrgDomains();
      return;
    } catch (e) {
      console.log(`Management API not ready (${e instanceof Error ? e.message : e}), retrying in 2s...`);
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
}

async function convergeOrgDomain(
  client: ZitadelClient,
  primaryDomain: string,
): Promise<void> {
  const domains = await client.listOrgDomains();
  const existing = domains.find((d) => d.domainName === primaryDomain);

  if (!existing) {
    console.log(`Adding org domain: ${primaryDomain}`);
    await client.addOrgDomain(primaryDomain);
    console.log(`Setting primary domain: ${primaryDomain}`);
    await client.setPrimaryOrgDomain(primaryDomain);
    return;
  }

  if (!existing.isPrimary) {
    console.log(`Setting primary domain: ${primaryDomain}`);
    await client.setPrimaryOrgDomain(primaryDomain);
    return;
  }

  console.log(`Org domain already converged: ${primaryDomain}`);
}

async function convergeOrgs(
  client: ZitadelClient,
  orgDomains: string[],
): Promise<Map<string, string>> {
  const orgMap = new Map<string, string>();
  const existingOrgs = await client.listOrgs();

  // An org "belongs" to a domain key when it carries that domain — in any
  // position, not just primary. Orgs predating the orgDomains rework are
  // named freely and must be adopted, never duplicated: creating a
  // lookalike org would silently split users and grants.
  const domainOwners = new Map<string, string>();
  for (const org of existingOrgs) {
    for (const d of await client.listOrgDomains(org.id)) {
      if (!domainOwners.has(d.domainName)) {
        domainOwners.set(d.domainName, org.id);
      }
    }
  }

  for (const domain of orgDomains) {
    const existingId = domainOwners.get(domain) ??
      existingOrgs.find((o) => o.primaryDomain === domain || o.name === domain)?.id;
    if (existingId) {
      console.log(`Org already exists: ${domain} (${existingId})`);
      orgMap.set(domain, existingId);
      continue;
    }

    console.log(`Creating org: ${domain}`);
    const orgId = await client.createOrg(domain);
    await client.addOrgDomain(domain, orgId);
    await client.setPrimaryOrgDomain(domain, orgId);
    console.log(`Created org: ${domain} (${orgId})`);
    orgMap.set(domain, orgId);
  }

  return orgMap;
}

async function convergeProjectGrants(
  client: ZitadelClient,
  projectId: string,
  grantedOrgIds: string[],
  roleKeys: string[],
): Promise<void> {
  const existing = await client.listProjectGrants(projectId);
  const existingOrgIds = new Set(existing.map((g) => g.grantedOrgId));

  for (const orgId of grantedOrgIds) {
    if (existingOrgIds.has(orgId)) {
      console.log(`Project grant already exists: ${orgId}`);
      continue;
    }
    console.log(`Granting project to org: ${orgId}`);
    await client.createProjectGrant(projectId, orgId, roleKeys);
  }
}

async function convergeDomainPolicy(
  client: ZitadelClient,
  desired: DesiredState["policies"]["domainPolicy"],
): Promise<void> {
  const current = await client.getDomainPolicy();

  if (
    (current.userLoginMustBeDomain ?? false) === desired.userLoginMustBeDomain &&
    (current.validateOrgDomains ?? false) === desired.validateOrgDomains
  ) {
    console.log("Domain policy already converged");
    return;
  }

  console.log("Updating domain policy");
  await client.updateDomainPolicy({
    userLoginMustBeDomain: desired.userLoginMustBeDomain,
    validateOrgDomains: desired.validateOrgDomains,
  });
}

async function convergeSecurityPolicy(
  client: ZitadelClient,
  enableImpersonation: boolean,
): Promise<void> {
  const current = await client.getSecurityPolicy();

  if ((current.enableImpersonation ?? false) === enableImpersonation) {
    console.log("Security policy already converged");
    return;
  }

  console.log(`Setting enableImpersonation=${enableImpersonation}`);
  await client.updateSecurityPolicy({
    // Sent alongside because the update replaces the policy wholesale;
    // omitting them would silently clear whatever is configured.
    enableIframeEmbedding: current.enableIframeEmbedding ?? false,
    allowedOrigins: current.allowedOrigins ?? [],
    enableImpersonation,
  });
}

// Additive by construction. Zitadel's member update REPLACES the role list,
// so the desired roles are unioned with what the account already holds —
// writing them alone would strip IAM_OWNER from the operator's own account.
async function convergeAdminIamRoles(
  client: ZitadelClient,
  adminUsername: string,
  desiredRoles: string[],
): Promise<void> {
  if (desiredRoles.length === 0) return;

  const users = await client.searchUsers();
  const admin = users.find((u) => u.userName === adminUsername);
  if (!admin) {
    console.log(`Admin user "${adminUsername}" not found, skipping IAM roles`);
    return;
  }

  const members = await client.searchIamMembers();
  const existing = members.find((m) => m.userId === admin.id);

  if (!existing) {
    console.log(`Adding ${adminUsername} as IAM member: ${desiredRoles.join(", ")}`);
    await client.addIamMember(admin.id, desiredRoles);
    return;
  }

  const missing = desiredRoles.filter((r) => !existing.roles.includes(r));
  if (missing.length === 0) {
    console.log("Admin IAM roles already converged");
    return;
  }

  const merged = [...existing.roles, ...missing];
  console.log(`Adding IAM roles to ${adminUsername}: ${missing.join(", ")}`);
  await client.updateIamMember(admin.id, merged);
}

async function convergeLoginPolicy(
  client: ZitadelClient,
  desired: DesiredState["policies"]["loginPolicy"],
): Promise<void> {
  const current = await client.getLoginPolicy();

  const registerMatch = (current.allowRegister ?? false) === desired.allowRegister;
  const externalMatch = (current.allowExternalIdp ?? false) === desired.allowExternalIdp;
  if (registerMatch && externalMatch) {
    console.log("Login policy already converged");
    return;
  }

  const { details: _, isDefault: __, ...settings } = current;
  console.log(`Setting allowRegister: ${desired.allowRegister}, allowExternalIdp: ${desired.allowExternalIdp}`);
  await client.updateLoginPolicy({
    ...settings,
    allowRegister: desired.allowRegister,
    allowExternalIdp: desired.allowExternalIdp,
  });
}

async function convergeUserEmails(
  client: ZitadelClient,
  primaryDomain: string,
): Promise<void> {
  const users = await client.searchUsers();

  for (const user of users) {
    if (!user.human?.email?.email) continue;

    const currentEmail = user.human.email.email;
    const atIdx = currentEmail.indexOf("@");
    if (atIdx < 0) continue;

    const currentDomain = currentEmail.substring(atIdx + 1);
    if (currentDomain === primaryDomain) continue;

    const localPart = currentEmail.substring(0, atIdx);
    const newEmail = `${localPart}@${primaryDomain}`;
    console.log(`Updating email for ${user.userName}: ${currentEmail} → ${newEmail}`);
    await client.updateUserEmail(user.id, newEmail);
  }

  console.log("User emails converged");
}

async function convergeProject(client: ZitadelClient, name: string): Promise<string> {
  const projects = await client.searchProjects(name);

  if (projects.length > 0) {
    const id = projects[0].id;
    const project = await client.getProject(id);

    if (!project.projectRoleAssertion) {
      console.log(`Enabling projectRoleAssertion on: ${name} (${id})`);
      await client.updateProject(id, { name: project.name, projectRoleAssertion: true });
    } else {
      console.log(`Project already converged: ${name} (${id})`);
    }

    return id;
  }

  console.log(`Creating project: ${name}`);
  const id = await client.createProject(name);
  console.log(`Created project: ${name} (${id})`);
  return id;
}

async function ensureParentDir(path: string): Promise<void> {
  const slash = path.lastIndexOf("/");
  if (slash > 0) {
    await Deno.mkdir(path.slice(0, slash), { recursive: true });
  }
}

// Write a credential file atomically: create the temp file with the final
// mode, fsync it, then rename into place. Zitadel cannot read a client
// secret back, so this file is the ONLY recoverable copy — a truncate-in-
// place write that is interrupted would destroy it, and the next converge
// run would see no stored secret and force-regenerate, silently
// invalidating every consumer's operator-carried copy. Mirrors what the
// operator-secrets daemon does for the same reason.
async function writeCredentialFile(
  path: string,
  contents: string,
): Promise<void> {
  await ensureParentDir(path);
  const tmp = `${path}.tmp.${Deno.pid}`;
  const file = await Deno.open(tmp, {
    write: true,
    createNew: true,
    mode: 0o600,
  });
  try {
    await file.write(new TextEncoder().encode(contents));
    await file.sync();
  } finally {
    file.close();
  }
  try {
    await Deno.rename(tmp, path);
  } catch (e) {
    await Deno.remove(tmp).catch(() => {});
    throw e;
  }
}

// Returns the CLIENT_SECRET previously written to `path`, but only if it
// still belongs to `clientId` — a recreated app gets a new client id, and
// its stale secret must not be handed back out.
async function readStoredClientSecret(
  path: string,
  clientId: string,
): Promise<string | null> {
  let text: string;
  try {
    text = await Deno.readTextFile(path);
  } catch (e) {
    // ONLY "the file is not there" means "nothing stored yet". Any other
    // failure — permissions, a transient I/O error, a directory in the
    // way — must fail the converge run loudly. Treating it as "absent"
    // would regenerate the client secret at Zitadel and overwrite the
    // still-good file, invalidating every consumer's copy until a human
    // re-enters the new value. This is the same error-vs-invalid
    // distinction operator-secrets is built around, applied on the
    // producing side.
    if (e instanceof Deno.errors.NotFound) {
      return null;
    }
    throw e;
  }

  const vars = new Map<string, string>();
  for (const line of text.split("\n")) {
    const eq = line.indexOf("=");
    if (eq > 0) {
      vars.set(line.slice(0, eq).trim(), line.slice(eq + 1).trim());
    }
  }

  if (vars.get("CLIENT_ID") !== clientId) {
    return null;
  }
  const secret = vars.get("CLIENT_SECRET");
  return secret !== undefined && secret.length > 0 ? secret : null;
}

async function convergeConfidentialApp(
  client: ZitadelClient,
  projectId: string,
  appName: string,
  spec: ConfidentialAppSpec,
): Promise<void> {
  const apps = await client.searchApps(projectId, appName);

  let clientId: string;
  let clientSecret: string;
  let appId: string;

  if (apps.length > 0) {
    const app = apps[0];
    appId = app.id;
    clientId = app.oidcConfig!.clientId;
    // Zitadel cannot read a client secret back, so the only way to keep
    // converge idempotent is to reuse the one we stored last time.
    // Regenerating unconditionally would invalidate every consumer's copy
    // on each run.
    const stored = await readStoredClientSecret(spec.outputPath, clientId);
    if (stored !== null) {
      console.log(`OIDC app exists: ${appName}, keeping stored client secret`);
      clientSecret = stored;
    } else {
      console.log(
        `OIDC app exists: ${appName}, but no stored secret for client ${clientId} — ` +
          "regenerating; consumers of this credential must be updated",
      );
      clientSecret = await client.regenerateClientSecret(projectId, appId);
    }
  } else {
    console.log(`Creating OIDC app: ${appName}`);
    const creds = await client.createOIDCApp(projectId, {
      name: appName,
      redirectUris: spec.redirectUris,
      responseTypes: ["OIDC_RESPONSE_TYPE_CODE"],
      grantTypes: zitadelGrantTypes(spec.grantTypes),
      appType: "OIDC_APP_TYPE_WEB",
      authMethodType: "OIDC_AUTH_METHOD_TYPE_BASIC",
      accessTokenType: zitadelAccessTokenType(spec.accessTokenType),
    });
    clientId = creds.clientId;
    clientSecret = creds.clientSecret;
    console.log(`Created OIDC app: ${appName} (client_id: ${clientId})`);

    const newApps = await client.searchApps(projectId, appName);
    appId = newApps.length > 0 ? newApps[0].id : "";
  }

  if (appId) {
    try {
      await client.updateOIDCAppConfig(projectId, appId, {
        redirectUris: spec.redirectUris,
        responseTypes: ["OIDC_RESPONSE_TYPE_CODE"],
        grantTypes: zitadelGrantTypes(spec.grantTypes),
        appType: "OIDC_APP_TYPE_WEB",
        authMethodType: "OIDC_AUTH_METHOD_TYPE_BASIC",
        accessTokenRoleAssertion: true,
        idTokenRoleAssertion: true,
        accessTokenType: zitadelAccessTokenType(spec.accessTokenType),
      });
      console.log(`Enabled role assertions on: ${appName}`);
    } catch (e) {
      if (e instanceof Error && e.message.includes("No changes")) {
        console.log(`Role assertions already set on: ${appName}`);
      } else {
        throw e;
      }
    }
  }

  await writeCredentialFile(
    spec.outputPath,
    [
      `CLIENT_ID=${clientId}`,
      `CLIENT_SECRET=${clientSecret}`,
      "",
    ].join("\n"),
  );
  console.log(`Wrote OIDC client credentials to ${spec.outputPath}`);
}

async function convergePublicApp(
  client: ZitadelClient,
  projectId: string,
  appName: string,
  spec: PublicAppSpec,
): Promise<void> {
  const apps = await client.searchApps(projectId, appName);

  let clientId: string;

  if (apps.length > 0) {
    const app = apps[0];
    clientId = app.oidcConfig!.clientId;
    console.log(`Public OIDC app exists: ${appName} (client_id: ${clientId})`);

    try {
      await client.updateOIDCAppConfig(projectId, app.id, {
        redirectUris: spec.redirectUris,
        postLogoutRedirectUris: spec.postLogoutRedirectUris,
        responseTypes: ["OIDC_RESPONSE_TYPE_CODE"],
        grantTypes: zitadelGrantTypes(spec.grantTypes),
        appType: "OIDC_APP_TYPE_USER_AGENT",
        authMethodType: "OIDC_AUTH_METHOD_TYPE_NONE",
        accessTokenRoleAssertion: true,
        idTokenRoleAssertion: true,
        accessTokenType: zitadelAccessTokenType(spec.accessTokenType),
      });
      console.log(`Updated config on: ${appName}`);
    } catch (e) {
      if (e instanceof Error && e.message.includes("already up to date")) {
        console.log(`Config already up to date: ${appName}`);
      } else {
        throw e;
      }
    }
  } else {
    console.log(`Creating public OIDC app: ${appName}`);
    const creds = await client.createOIDCApp(projectId, {
      name: appName,
      redirectUris: spec.redirectUris,
      postLogoutRedirectUris: spec.postLogoutRedirectUris,
      responseTypes: ["OIDC_RESPONSE_TYPE_CODE"],
      grantTypes: zitadelGrantTypes(spec.grantTypes),
      appType: "OIDC_APP_TYPE_USER_AGENT",
      authMethodType: "OIDC_AUTH_METHOD_TYPE_NONE",
      accessTokenRoleAssertion: true,
      idTokenRoleAssertion: true,
      accessTokenType: zitadelAccessTokenType(spec.accessTokenType),
    });
    clientId = creds.clientId;
    console.log(`Created public OIDC app: ${appName} (client_id: ${clientId})`);
  }

  await Deno.writeTextFile(spec.outputPath, clientId);
  console.log(`Wrote OIDC client ID to ${spec.outputPath}`);
}

async function convergeProjectRole(
  client: ZitadelClient,
  projectId: string,
  roleKey: string,
  displayName: string,
): Promise<void> {
  const roles = await client.searchProjectRoles(projectId);
  if (roles.some((r) => r.key === roleKey)) {
    console.log(`Project role already exists: ${roleKey}`);
    return;
  }

  console.log(`Creating project role: ${roleKey}`);
  await client.addProjectRole(projectId, roleKey, displayName);
}

// Created once and then left alone: a password reset or a renamed display
// name is the operator's to make, and re-imposing either on every deploy
// would undo it.
async function convergeUsers(
  client: ZitadelClient,
  users: DesiredState["users"],
  adminOrg: string,
): Promise<void> {
  if (!users || users.length === 0) return;

  const existing = await client.searchUsers();

  for (const user of users) {
    // The login name carries the org domain, and it is also the mailbox
    // address, so the account is addressed the same way everywhere.
    const loginName = `${user.username}@${adminOrg}`;

    if (existing.some((u) => u.userName === user.username || u.userName === loginName)) {
      console.log(`User already exists: ${user.username}`);
      continue;
    }

    const password = (await Deno.readTextFile(user.passwordPath)).trim();
    console.log(`Creating user: ${loginName}`);
    await client.createHumanUser(user.username, user.displayName, loginName, password);
  }
}

async function convergeUserGrant(
  client: ZitadelClient,
  projectId: string,
  userName: string,
  roleKeys: string[],
): Promise<void> {
  const users = await client.searchUsers();
  const user = users.find((u) => u.userName === userName);
  if (!user) {
    console.log(`User "${userName}" not found, skipping grant`);
    return;
  }

  const grants = await client.searchUserGrants(user.id, projectId);
  if (grants.length > 0) {
    const grant = grants[0];
    const missing = roleKeys.filter((k) => !grant.roleKeys.includes(k));
    if (missing.length === 0) {
      console.log(`User "${userName}" already has all roles: ${roleKeys.join(", ")}`);
      return;
    }
    console.log(`Adding roles ${missing.join(", ")} to user "${userName}"`);
    await client.updateUserGrant(user.id, grant.id, [...new Set([...grant.roleKeys, ...roleKeys])]);
    return;
  }

  console.log(`Granting roles ${roleKeys.join(", ")} to user "${userName}"`);
  await client.createUserGrant(user.id, projectId, roleKeys);
}

const FLOW_TYPE_IDS: Record<string, string> = {
  externalAuthentication: "1",
  complementToken: "2",
  internalAuthentication: "3",
  complementSAMLResponse: "4",
};

const TRIGGER_TYPE_IDS: Record<string, string> = {
  postAuthentication: "1",
  preCreation: "2",
  postCreation: "3",
  preUserinfoCreation: "4",
  preAccessTokenCreation: "5",
  preSAMLResponseCreation: "6",
};

async function convergeActions(
  client: ZitadelClient,
  actions: Record<string, ActionSpec>,
): Promise<void> {
  if (Object.keys(actions).length === 0) return;

  const existing = await client.listActions();
  const actionIdByName: Record<string, string> = {};

  for (const [name, spec] of Object.entries(actions)) {
    const found = existing.find((a) => a.name === name);

    if (found) {
      if (found.script !== spec.script || found.timeout !== spec.timeout || found.allowedToFail !== spec.allowedToFail) {
        console.log(`Updating action: ${name}`);
        await client.updateAction(found.id, {
          name,
          script: spec.script,
          timeout: spec.timeout,
          allowedToFail: spec.allowedToFail,
        });
      } else {
        console.log(`Action already converged: ${name}`);
      }
      actionIdByName[name] = found.id;
    } else {
      console.log(`Creating action: ${name}`);
      const id = await client.createAction({
        name,
        script: spec.script,
        timeout: spec.timeout,
        allowedToFail: spec.allowedToFail,
      });
      actionIdByName[name] = id;
      console.log(`Created action: ${name} (${id})`);
    }
  }

  // Group triggers by flow+trigger combination
  const triggerMap: Record<string, string[]> = {};
  for (const [name, spec] of Object.entries(actions)) {
    for (const trigger of spec.triggers) {
      const flowId = FLOW_TYPE_IDS[trigger.flowType];
      const triggerId = TRIGGER_TYPE_IDS[trigger.triggerType];
      const key = `${flowId}:${triggerId}`;
      if (!triggerMap[key]) triggerMap[key] = [];
      triggerMap[key].push(actionIdByName[name]);
    }
  }

  // Wire actions to their flow triggers
  for (const [key, actionIds] of Object.entries(triggerMap)) {
    const [flowId, triggerId] = key.split(":");
    const flow = await client.getFlow(flowId);
    const existingTrigger = flow.triggerActions.find((t) => t.triggerType.id === triggerId);
    const existingIds = existingTrigger?.actions.map((a) => a.id) ?? [];

    const needsUpdate = actionIds.length !== existingIds.length ||
      actionIds.some((id, i) => existingIds[i] !== id);

    if (needsUpdate) {
      console.log(`Setting trigger actions: flow=${flowId} trigger=${triggerId} → [${actionIds.join(", ")}]`);
      await client.setTriggerActions(flowId, triggerId, actionIds);
    } else {
      console.log(`Trigger already wired: flow=${flowId} trigger=${triggerId}`);
    }
  }
}

async function convergeInstancePasswordComplexity(
  client: ZitadelClient,
  desired: PasswordComplexityPolicy,
): Promise<void> {
  console.log("Updating instance password complexity policy");
  await client.updatePasswordComplexityPolicy(desired);
}

async function uploadBrandingAssets(
  client: ZitadelClient,
  prefix: string,
  desired: LabelPolicy,
): Promise<void> {
  const assets: [string | null, string][] = [
    [desired.logoUrl, `${prefix}/policy/label/logo`],
    [desired.logoUrlDark, `${prefix}/policy/label/logo/dark`],
    [desired.iconUrl, `${prefix}/policy/label/icon`],
    [desired.iconUrlDark, `${prefix}/policy/label/icon/dark`],
    [desired.fontUrl, `${prefix}/policy/label/font`],
  ];
  for (const [filePath, uploadPath] of assets) {
    if (filePath) {
      console.log(`Uploading asset: ${uploadPath} ← ${filePath}`);
      await client.uploadAsset(uploadPath, filePath);
    }
  }
}

async function convergeInstanceBranding(
  client: ZitadelClient,
  desired: LabelPolicy,
): Promise<void> {
  console.log("Updating instance branding");
  await client.updateLabelPolicy(desired);
  await uploadBrandingAssets(client, "/assets/v1/instance", desired);
  await client.activateLabelPolicy();
  console.log("Instance branding activated");
}

async function convergeInstanceLanguages(
  client: ZitadelClient,
  languages: { default: string | null; allowed: string[] | null },
): Promise<void> {
  if (languages.default) {
    console.log(`Setting default language: ${languages.default}`);
    await client.setDefaultLanguage(languages.default);
  }
  if (languages.allowed) {
    console.log(`Setting allowed languages: ${languages.allowed.join(", ")}`);
    await client.setRestrictions({ allowedLanguages: { list: languages.allowed } });
  }
}

async function convergeInstanceOIDCSettings(
  client: ZitadelClient,
  settings: NonNullable<InstanceSettings["oidcSettings"]>,
): Promise<void> {
  console.log("Updating OIDC settings");
  await client.updateOIDCSettings({
    accessTokenLifetime: `${settings.accessTokenLifetimeSeconds}s`,
    idTokenLifetime: `${settings.idTokenLifetimeSeconds}s`,
    refreshTokenExpiration: `${settings.refreshTokenExpirationSeconds}s`,
    refreshTokenIdleExpiration: `${settings.refreshTokenIdleExpirationSeconds}s`,
  });
}

const SECRET_GENERATOR_TYPES: Record<string, string> = {
  initializationMail: "1",
  emailVerification: "2",
  phoneVerification: "3",
  passwordReset: "4",
  passwordlessInitialization: "5",
  appSecret: "6",
  otpSms: "7",
  otpEmail: "8",
};

async function convergeInstanceSecretGenerators(
  client: ZitadelClient,
  generators: Record<string, SecretGeneratorConfig>,
): Promise<void> {
  for (const [name, config] of Object.entries(generators)) {
    const typeId = SECRET_GENERATOR_TYPES[name];
    if (!typeId) {
      console.log(`Unknown secret generator type: ${name}, skipping`);
      continue;
    }
    console.log(`Updating secret generator: ${name}`);
    await client.updateSecretGenerator(typeId, config);
  }
}

async function convergeOrgPasswordComplexity(
  client: ZitadelClient,
  desired: PasswordComplexityPolicy,
): Promise<void> {
  const { policy } = await client.getOrgPasswordComplexityPolicy();
  if (policy.isDefault) {
    console.log("Adding custom org password complexity policy");
    await client.addCustomPasswordComplexityPolicy(desired);
  } else {
    console.log("Updating custom org password complexity policy");
    await client.updateCustomPasswordComplexityPolicy(desired);
  }
}

async function convergeOrgBranding(
  client: ZitadelClient,
  desired: LabelPolicy,
): Promise<void> {
  const { policy } = await client.getOrgLabelPolicy();
  if (policy.isDefault) {
    console.log("Adding custom org branding");
    await client.addCustomLabelPolicy(desired);
  } else {
    console.log("Updating custom org branding");
    await client.updateCustomLabelPolicy(desired);
  }
  await uploadBrandingAssets(client, "/assets/v1/org", desired);
  await client.activateCustomLabelPolicy();
  console.log("Org branding activated");
}

async function convergePrivacyPolicy(
  client: ZitadelClient,
  link: string | null,
): Promise<void> {
  if (!link) {
    console.log("No privacy policy link configured, skipping");
    return;
  }

  const current = await client.getPrivacyPolicy();
  if (current.privacyLink === link) {
    console.log("Privacy policy link already converged");
    return;
  }

  console.log(`Setting privacy policy link: ${link}`);
  await client.updatePrivacyPolicy({
    ...current,
    privacyLink: link,
  });
}

async function main(): Promise<void> {
  const specPath = Deno.args[0];
  if (!specPath) {
    console.error("Usage: zitadel-configure.ts <desired-state.json>");
    Deno.exit(1);
  }

  const spec: DesiredState = JSON.parse(await Deno.readTextFile(specPath));
  const token = (await Deno.readTextFile(spec.patPath)).trim();
  const client = new ZitadelClient(spec.apiUrl, token);

  await waitForApi(client);
  await convergeDomainPolicy(client, spec.policies.domainPolicy);
  await convergeLoginPolicy(client, spec.policies.loginPolicy);
  await convergeSecurityPolicy(client, spec.policies.enableImpersonation);
  await convergeAdminIamRoles(client, spec.adminUsername, spec.adminIamRoles);
  await convergeUsers(client, spec.users, spec.adminOrg);

  await convergeOrgDomain(client, spec.adminOrg);
  await convergeUserEmails(client, spec.adminOrg);
  await convergePrivacyPolicy(client, spec.privacyPolicyLink);

  const orgMap = await convergeOrgs(client, spec.orgDomains);

  if (spec.policies.disallowPublicOrgRegistration) {
    console.log("Disabling public organization registration");
    await client.setRestrictions({ disallowPublicOrgRegistration: true });
  }

  // Instance-level settings
  if (spec.instance) {
    if (spec.instance.passwordComplexity) {
      await convergeInstancePasswordComplexity(client, spec.instance.passwordComplexity);
    }
    if (spec.instance.branding) {
      await convergeInstanceBranding(client, spec.instance.branding);
    }
    if (spec.instance.languages) {
      await convergeInstanceLanguages(client, spec.instance.languages);
    }
    if (spec.instance.oidcSettings) {
      await convergeInstanceOIDCSettings(client, spec.instance.oidcSettings);
    }
    if (spec.instance.secretGenerators) {
      await convergeInstanceSecretGenerators(client, spec.instance.secretGenerators);
    }
  }

  // Org-level settings
  if (spec.orgs) {
    for (const [_orgName, orgSettings] of Object.entries(spec.orgs)) {
      if (orgSettings.passwordComplexity) {
        await convergeOrgPasswordComplexity(client, orgSettings.passwordComplexity);
      }
      if (orgSettings.branding) {
        await convergeOrgBranding(client, orgSettings.branding);
      }
    }
  }

  const allOrgIds = spec.orgDomains.map((d) => orgMap.get(d)!).filter(Boolean);
  const adminOrgId = orgMap.get(spec.adminOrg)!;
  const grantedOrgIds = allOrgIds.filter((id) => id !== adminOrgId);

  for (const [projectName, projectSpec] of Object.entries(spec.projects)) {
    const projectId = await convergeProject(client, projectName);

    for (const [appName, appSpec] of Object.entries(projectSpec.apps)) {
      if (appSpec.type === "confidential") {
        await convergeConfidentialApp(client, projectId, appName, appSpec as ConfidentialAppSpec);
      } else {
        await convergePublicApp(client, projectId, appName, appSpec as PublicAppSpec);
      }
    }

    for (const [roleKey, roleSpec] of Object.entries(projectSpec.roles)) {
      await convergeProjectRole(client, projectId, roleKey, roleSpec.displayName);
    }

    for (const [userName, roleKeys] of Object.entries(projectSpec.userGrants)) {
      await convergeUserGrant(client, projectId, userName, roleKeys);
    }

    if (grantedOrgIds.length > 0) {
      const roleKeys = Object.keys(projectSpec.roles);
      await convergeProjectGrants(client, projectId, grantedOrgIds, roleKeys);
    }
  }

  await convergeActions(client, spec.actions);

  console.log("Configuration complete");
}

main();
