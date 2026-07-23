//! oidc-credential-validator — proves a set of OIDC client credentials
//! good, bad, or undecidable, speaking the validator protocol from
//! docs/operator-secrets.md.
//!
//! stdin  <- one JSON object: {"fields": {"CLIENT_ID": "…", "CLIENT_SECRET": "…"}}
//! stdout -> one JSON object: {"status": "valid"|"invalid"|"error", "message": "…"}
//!
//! The credentials arrive on stdin and leave only in an Authorization
//! header or a POST body over TLS; they never touch argv, the
//! environment, or any log. Nothing here knows about any particular
//! identity provider — it is discovery plus a standard probe that makes
//! the credential provably good:
//!
//! - Preferred: RFC 7662 token introspection with a throwaway token.
//!   Authenticating the introspection call IS the proof; the (always
//!   inactive) result for the dummy token is irrelevant. This needs no
//!   grant on the client, and works for app clients on providers that
//!   reserve client_credentials for service accounts (Zitadel does —
//!   correct app credentials get `invalid_client` from its token
//!   endpoint, which would read as a wrong secret).
//! - Fallback, when no introspection_endpoint is advertised: a
//!   client_credentials token request.
//!
//! The load-bearing distinction is `invalid` vs `error`: `invalid` means
//! the server looked at these credentials and rejected them; `error`
//! means we could not get an answer (DNS, TLS, timeout, 5xx, malformed
//! discovery). Only `invalid` may cause a stored secret to be replaced,
//! so anything we are not certain about must be `error`.

use std::collections::BTreeMap;
use std::io::Read;
use std::time::Duration;

use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Request {
    fields: BTreeMap<String, String>,
}

#[derive(Serialize)]
struct Response {
    status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

enum Verdict {
    Valid(String),
    Invalid(String),
    Error(String),
}

impl Verdict {
    fn emit(self) -> ! {
        let (status, message) = match self {
            Verdict::Valid(m) => ("valid", m),
            Verdict::Invalid(m) => ("invalid", m),
            Verdict::Error(m) => ("error", m),
        };
        let r = Response {
            status,
            message: if message.is_empty() {
                None
            } else {
                Some(message)
            },
        };
        // The daemon reads `status`, not the exit code; a serialization
        // failure here would be indistinguishable from a crash, and a
        // crash is `error` on the daemon's side either way.
        println!(
            "{}",
            serde_json::to_string(&r).unwrap_or_else(|_| {
                r#"{"status":"error","message":"could not serialize verdict"}"#.into()
            })
        );
        std::process::exit(0)
    }
}

struct Args {
    issuer: String,
    client_id_field: String,
    client_secret_field: String,
    scope: Option<String>,
    timeout: Duration,
    allow_insecure_http: bool,
}

const USAGE: &str = "\
oidc-credential-validator --issuer <URL> [options]

Reads {\"fields\":{...}} on stdin, writes {\"status\":...} on stdout.

  --issuer <URL>              OIDC issuer; <issuer>/.well-known/openid-configuration
                              is fetched to discover the token endpoint. Required.
  --client-id-field <NAME>    stdin field holding the client id     [CLIENT_ID]
  --client-secret-field <N>   stdin field holding the client secret [CLIENT_SECRET]
  --scope <SCOPE>             scope for the token request           [none]
  --timeout-secs <N>          per-request timeout                   [15]
  --allow-insecure-http       permit a plain-http issuer (testing only)
  -h, --help                  this text
";

/// Hand-rolled because this binary must not grow a dependency surface it
/// does not need; it is spawned with a fixed argv by the daemon.
fn parse_args() -> Result<Args, String> {
    let mut issuer = None;
    let mut client_id_field = "CLIENT_ID".to_string();
    let mut client_secret_field = "CLIENT_SECRET".to_string();
    let mut scope = None;
    let mut timeout = 15u64;
    let mut allow_insecure_http = false;

    let mut argv = std::env::args().skip(1);
    while let Some(arg) = argv.next() {
        let mut value = |flag: &str| argv.next().ok_or_else(|| format!("{flag} needs a value"));
        match arg.as_str() {
            "--issuer" => issuer = Some(value("--issuer")?),
            "--client-id-field" => client_id_field = value("--client-id-field")?,
            "--client-secret-field" => client_secret_field = value("--client-secret-field")?,
            "--scope" => scope = Some(value("--scope")?),
            "--timeout-secs" => {
                let v = value("--timeout-secs")?;
                timeout = v
                    .parse()
                    .map_err(|_| format!("--timeout-secs {v:?} is not a number"))?;
            }
            "--allow-insecure-http" => allow_insecure_http = true,
            "-h" | "--help" => {
                print!("{USAGE}");
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument {other:?}")),
        }
    }

    Ok(Args {
        issuer: issuer.ok_or("--issuer is required")?,
        client_id_field,
        client_secret_field,
        scope,
        timeout: Duration::from_secs(timeout),
        allow_insecure_http,
    })
}

fn main() {
    // Every failure below is `error`, not `invalid`: a validator that
    // cannot run has not judged anything.
    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => Verdict::Error(format!("bad invocation: {e}")).emit(),
    };

    let mut input = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut input) {
        Verdict::Error(format!("reading stdin: {e}")).emit();
    }
    let request: Request = match serde_json::from_str(&input) {
        Ok(r) => r,
        Err(e) => Verdict::Error(format!("stdin is not a validator request: {e}")).emit(),
    };

    let Some(client_id) = request.fields.get(&args.client_id_field) else {
        Verdict::Error(format!("stdin has no {} field", args.client_id_field)).emit()
    };
    let Some(client_secret) = request.fields.get(&args.client_secret_field) else {
        Verdict::Error(format!("stdin has no {} field", args.client_secret_field)).emit()
    };

    check(&args, client_id, client_secret).emit()
}

fn agent(args: &Args) -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(args.timeout))
        // A redirect off the issuer's host would send the credentials
        // somewhere the operator never named.
        .max_redirects(0)
        // A 4xx from the token endpoint is the interesting case, not an
        // error: its BODY carries the OAuth error code that separates a
        // rejected credential (`invalid_client` -> invalid) from a
        // refused grant (-> error, nothing was judged). ureq's default
        // turns non-2xx into an Err and throws the body away, which would
        // collapse that distinction into a guess.
        .http_status_as_error(false)
        .build()
        .into()
}

fn check(args: &Args, client_id: &str, client_secret: &str) -> Verdict {
    let issuer = args.issuer.trim_end_matches('/');
    if !issuer.starts_with("https://") && !args.allow_insecure_http {
        return Verdict::Error(format!(
            "issuer {issuer:?} is not https; refusing to send credentials in the clear"
        ));
    }

    let agent = agent(args);
    let discovery_url = format!("{issuer}/.well-known/openid-configuration");

    // Nothing that goes wrong here is ever `invalid`: discovery does not
    // look at the credentials, so a 404 or a broken document says the
    // issuer URL is wrong, not that the secret is.
    let doc: serde_json::Value = match agent.get(&discovery_url).call() {
        Ok(mut resp) => {
            let status = resp.status().as_u16();
            if !(200..300).contains(&status) {
                return Verdict::Error(format!("{discovery_url} returned HTTP {status}"));
            }
            match resp.body_mut().read_to_string() {
                Ok(body) => match serde_json::from_str(&body) {
                    Ok(v) => v,
                    Err(e) => return Verdict::Error(format!("{discovery_url} is not JSON: {e}")),
                },
                Err(e) => return Verdict::Error(format!("reading {discovery_url}: {e}")),
            }
        }
        Err(e) => return Verdict::Error(format!("fetching {discovery_url}: {e}")),
    };

    // Preferred probe: RFC 7662 introspection, when advertised. See the
    // module docs for why (grant-free, and the only sound probe on
    // providers like Zitadel). When the endpoint is advertised it is THE
    // probe — a decisive `invalid` from it must not cascade into a
    // misleading second opinion from the token endpoint.
    if let Some(endpoint) = doc.get("introspection_endpoint").and_then(|v| v.as_str()) {
        if !endpoint.starts_with("https://") && !args.allow_insecure_http {
            return Verdict::Error(format!(
                "introspection_endpoint {endpoint:?} is not https; refusing to send credentials in the clear"
            ));
        }
        let methods =
            match negotiated_methods(&doc, "introspection_endpoint_auth_methods_supported") {
                Ok(m) => m,
                Err(e) => return Verdict::Error(e),
            };
        return try_methods(methods, |method| {
            introspection_request(&agent, endpoint, client_id, client_secret, method)
        });
    }

    let Some(token_endpoint) = doc.get("token_endpoint").and_then(|v| v.as_str()) else {
        return Verdict::Error(format!(
            "{discovery_url} declares neither introspection_endpoint nor token_endpoint"
        ));
    };
    if !token_endpoint.starts_with("https://") && !args.allow_insecure_http {
        return Verdict::Error(format!(
            "token_endpoint {token_endpoint:?} is not https; refusing to send credentials in the clear"
        ));
    }

    let methods = match negotiated_methods(&doc, "token_endpoint_auth_methods_supported") {
        Ok(m) => m,
        Err(e) => return Verdict::Error(e),
    };
    try_methods(methods, |method| {
        token_request(
            args,
            &agent,
            token_endpoint,
            client_id,
            client_secret,
            method,
        )
    })
}

/// Try each negotiated auth method until one yields a decision other than
/// `invalid` — a provider that only accepts client_secret_post answers a
/// Basic attempt with invalid_client, which would otherwise read as a
/// wrong credential.
fn try_methods(methods: Vec<AuthMethod>, mut req: impl FnMut(AuthMethod) -> Verdict) -> Verdict {
    let mut last_invalid = None;
    for method in methods {
        match req(method) {
            Verdict::Invalid(m) => last_invalid = Some(m),
            other => return other,
        }
    }
    Verdict::Invalid(last_invalid.unwrap_or_else(|| "credentials rejected".into()))
}

/// Auth methods to attempt, honoring what the provider advertises under
/// `key`; both when it advertises nothing.
fn negotiated_methods(doc: &serde_json::Value, key: &str) -> Result<Vec<AuthMethod>, String> {
    let supported: Vec<String> = doc
        .get(key)
        .and_then(|v| v.as_array())
        .map(|a| {
            a.iter()
                .filter_map(|v| v.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    if supported.is_empty() {
        return Ok(vec![AuthMethod::Basic, AuthMethod::Post]);
    }
    let mut methods = Vec::new();
    if supported.iter().any(|m| m == "client_secret_basic") {
        methods.push(AuthMethod::Basic);
    }
    if supported.iter().any(|m| m == "client_secret_post") {
        methods.push(AuthMethod::Post);
    }
    if methods.is_empty() {
        return Err(format!(
            "{key} lists none of client_secret_basic/client_secret_post (advertises {supported:?})"
        ));
    }
    Ok(methods)
}

#[derive(Clone, Copy)]
enum AuthMethod {
    Basic,
    Post,
}

/// RFC 7662 probe: introspect a throwaway token. The server must
/// authenticate the CLIENT before answering, so a well-formed answer at
/// all (`active` present — inevitably false for our dummy) proves the
/// client id/secret; a 401/invalid_client disproves it. The one soundness
/// assumption is that the endpoint authenticates clients — RFC 7662 §2.1
/// requires it, and a provider that skipped it would false-accept.
fn introspection_request(
    agent: &ureq::Agent,
    endpoint: &str,
    client_id: &str,
    client_secret: &str,
    method: AuthMethod,
) -> Verdict {
    let mut form: Vec<(&str, &str)> = vec![("token", "operator-secrets-liveness-probe")];
    if matches!(method, AuthMethod::Post) {
        form.push(("client_id", client_id));
        form.push(("client_secret", client_secret));
    }

    let mut req = agent.post(endpoint).header("Accept", "application/json");
    if matches!(method, AuthMethod::Basic) {
        // RFC 6749 §2.3.1: form-urlencode both halves, then base64 the
        // `id:secret` pair.
        let creds = format!(
            "{}:{}",
            form_urlencode(client_id),
            form_urlencode(client_secret)
        );
        req = req.header(
            "Authorization",
            format!("Basic {}", base64(creds.as_bytes())),
        );
    }

    match req.send_form(form) {
        Ok(mut resp) => {
            let status = resp.status().as_u16();
            let body = resp.body_mut().read_to_string().unwrap_or_default();
            classify_introspection(status, &body)
        }
        Err(e) => Verdict::Error(format!("introspection request to {endpoint}: {e}")),
    }
}

fn classify_introspection(status: u16, body: &str) -> Verdict {
    if (200..300).contains(&status) {
        return match serde_json::from_str::<serde_json::Value>(body)
            .ok()
            .and_then(|v| v.get("active").and_then(|a| a.as_bool()))
        {
            Some(_) => Verdict::Valid(
                "introspection endpoint authenticated the client (RFC 7662 probe)".into(),
            ),
            // 2xx without the mandatory `active` field is not an RFC 7662
            // introspection response; nothing was proven.
            None => Verdict::Error(format!(
                "introspection endpoint answered HTTP {status} without an `active` field; cannot decide"
            )),
        };
    }
    if status >= 500 || status == 429 {
        return Verdict::Error(format!(
            "introspection endpoint returned HTTP {status}; cannot decide"
        ));
    }

    let error = serde_json::from_str::<serde_json::Value>(body)
        .ok()
        .and_then(|v| v.get("error").and_then(|e| e.as_str()).map(str::to_string));
    let described = error.clone().unwrap_or_else(|| format!("HTTP {status}"));
    match error.as_deref() {
        Some("invalid_client") => Verdict::Invalid(format!(
            "introspection endpoint rejected the credentials ({described})"
        )),
        None if status == 401 || status == 403 => Verdict::Invalid(format!(
            "introspection endpoint rejected the credentials ({described})"
        )),
        _ => Verdict::Error(format!(
            "introspection endpoint answered HTTP {status} ({described}); cannot decide"
        )),
    }
}

fn token_request(
    args: &Args,
    agent: &ureq::Agent,
    token_endpoint: &str,
    client_id: &str,
    client_secret: &str,
    method: AuthMethod,
) -> Verdict {
    let mut form: Vec<(&str, &str)> = vec![("grant_type", "client_credentials")];
    if let Some(scope) = &args.scope {
        form.push(("scope", scope));
    }
    // client_id is not secret and several providers want it regardless.
    form.push(("client_id", client_id));
    if matches!(method, AuthMethod::Post) {
        form.push(("client_secret", client_secret));
    }

    let mut req = agent
        .post(token_endpoint)
        .header("Accept", "application/json");
    if matches!(method, AuthMethod::Basic) {
        // RFC 6749 §2.3.1: form-urlencode both halves, then base64 the
        // `id:secret` pair.
        let creds = format!(
            "{}:{}",
            form_urlencode(client_id),
            form_urlencode(client_secret)
        );
        req = req.header(
            "Authorization",
            format!("Basic {}", base64(creds.as_bytes())),
        );
    }

    let (status, body) = match req.send_form(form) {
        Ok(mut resp) => {
            let status = resp.status().as_u16();
            (status, resp.body_mut().read_to_string().unwrap_or_default())
        }
        Err(e) => return Verdict::Error(format!("token request to {token_endpoint}: {e}")),
    };

    if (200..300).contains(&status) {
        // The server minted a token for these credentials. Proven good.
        return Verdict::Valid(format!(
            "token endpoint accepted the credentials (HTTP {status})"
        ));
    }
    if status >= 500 || status == 429 {
        // The server did not judge the credentials, it failed or throttled.
        return Verdict::Error(format!(
            "token endpoint returned HTTP {status}; cannot decide"
        ));
    }

    let error = serde_json::from_str::<serde_json::Value>(&body)
        .ok()
        .and_then(|v| v.get("error").and_then(|e| e.as_str()).map(str::to_string));
    let described = error.clone().unwrap_or_else(|| format!("HTTP {status}"));

    // Only a minted token proves a credential good. It is tempting to
    // read "grant refused" as "authentication succeeded, so the secret is
    // fine" — RFC 6749 even words `unauthorized_client` as being about
    // the *authenticated* client. Real providers do not honour that:
    // accounts.google.com answers `unsupported_grant_type` to entirely
    // made-up credentials, because it rejects the grant type before it
    // ever looks at who is asking. Trusting that wording would mark
    // garbage `valid` and release the boot — the exact failure this
    // mechanism exists to prevent. So a refused grant is `error`: the
    // boot parks with an explanation and nothing is written or discarded.
    match error.as_deref() {
        // The one unambiguous statement that these credentials are wrong.
        Some("invalid_client") => Verdict::Invalid(format!(
            "token endpoint rejected the credentials ({described})"
        )),
        // The server never judged the credentials.
        Some(
            "unsupported_grant_type"
            | "unauthorized_client"
            | "invalid_scope"
            | "invalid_grant"
            | "invalid_request",
        ) => Verdict::Error(format!(
            "token endpoint refused the client_credentials grant ({described}) without judging \
             the credentials — this client cannot be validated this way; enable the \
             client_credentials grant for it, or use a different validator"
        )),
        // No recognizable OAuth error. A bare 401/403 from a token
        // endpoint is an authentication failure; anything else is not
        // something we are willing to call a wrong credential.
        None if status == 401 || status == 403 => Verdict::Invalid(format!(
            "token endpoint rejected the credentials ({described})"
        )),
        _ => Verdict::Error(format!(
            "token endpoint answered HTTP {status} ({described}); cannot decide"
        )),
    }
}

/// `application/x-www-form-urlencoded` escaping, per RFC 6749 §2.3.1.
fn form_urlencode(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => {
                out.push(b as char)
            }
            b' ' => out.push('+'),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

fn base64(input: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(input.len().div_ceil(3) * 4);
    for chunk in input.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = u32::from(b[0]) << 16 | u32::from(b[1]) << 8 | u32::from(b[2]);
        out.push(T[(n >> 18 & 63) as usize] as char);
        out.push(T[(n >> 12 & 63) as usize] as char);
        out.push(if chunk.len() > 1 {
            T[(n >> 6 & 63) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            T[(n & 63) as usize] as char
        } else {
            '='
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_matches_rfc4648_vectors() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foob"), "Zm9vYg==");
        assert_eq!(base64(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
        // The realistic case: a client id/secret pair.
        assert_eq!(base64(b"client:s3cr3t"), "Y2xpZW50OnMzY3IzdA==");
    }

    #[test]
    fn form_urlencoding_escapes_everything_awkward() {
        assert_eq!(form_urlencode("plain-id_1.0~x"), "plain-id_1.0~x");
        assert_eq!(form_urlencode("a b"), "a+b");
        // A secret containing ':' must not be able to move the Basic
        // credential boundary.
        assert_eq!(form_urlencode("a:b"), "a%3Ab");
        assert_eq!(form_urlencode("p@ss/w+rd%"), "p%40ss%2Fw%2Brd%25");
        assert_eq!(form_urlencode("ü"), "%C3%BC");
    }

    #[test]
    fn introspection_classification_holds_the_invariants() {
        // Authenticated: `active` present (its value is irrelevant — the
        // dummy token is always inactive).
        assert!(matches!(
            classify_introspection(200, r#"{"active":false}"#),
            Verdict::Valid(_)
        ));
        assert!(matches!(
            classify_introspection(200, r#"{"active":true}"#),
            Verdict::Valid(_)
        ));
        // 2xx that is not an introspection response proves nothing.
        assert!(matches!(
            classify_introspection(200, r#"{"ok":1}"#),
            Verdict::Error(_)
        ));
        // Client rejected.
        assert!(matches!(
            classify_introspection(401, r#"{"error":"invalid_client"}"#),
            Verdict::Invalid(_)
        ));
        assert!(matches!(
            classify_introspection(401, ""),
            Verdict::Invalid(_)
        ));
        // Server trouble / unrecognized shapes never count as invalid.
        assert!(matches!(classify_introspection(503, ""), Verdict::Error(_)));
        assert!(matches!(classify_introspection(429, ""), Verdict::Error(_)));
        assert!(matches!(
            classify_introspection(400, r#"{"error":"invalid_request"}"#),
            Verdict::Error(_)
        ));
    }

    #[test]
    fn verdict_json_shape_matches_the_protocol() {
        let with = serde_json::to_string(&Response {
            status: "invalid",
            message: Some("nope".into()),
        })
        .unwrap();
        assert_eq!(with, r#"{"status":"invalid","message":"nope"}"#);
        let without = serde_json::to_string(&Response {
            status: "valid",
            message: None,
        })
        .unwrap();
        assert_eq!(without, r#"{"status":"valid"}"#);
    }
}
