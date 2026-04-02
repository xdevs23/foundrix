---
title: "Privacy Policy - {{ (ds "config").organization.name }}"
lang: en
---

# Privacy Policy

**{{ (ds "config").organization.name }}**

Last updated: {{ (ds "config").document.last_updated }}

---

## 1. Introduction

This privacy policy explains how {{ (ds "config").organization.name }} ("we", "us", "our") collects, uses, and protects your personal data when you use our identity and authentication services. We process your data in accordance with the General Data Protection Regulation (GDPR).

---

## 2. Data Controller

**{{ (ds "config").organization.name }}**
{{ if (ds "config").organization.address }}{{ (ds "config").organization.address }}
{{ end }}
Email: {{ (ds "config").contact.email }}

---

## 3. Data We Collect

We collect only the data necessary to provide identity and authentication services.

### 3.1 Account Data

| Data | Purpose | Legal Basis |
|------|---------|-------------|
| Email address | Account identification, recovery, essential notifications | Contract performance (Art. 6(1)(b) GDPR) |
| User ID | Technical account identification | Contract performance (Art. 6(1)(b) GDPR) |
| Name | Display within the service | Contract performance (Art. 6(1)(b) GDPR) |
| Password (hashed) | Authentication | Contract performance (Art. 6(1)(b) GDPR) |

### 3.2 Authentication Data

| Data | Purpose | Legal Basis |
|------|---------|-------------|
| Login timestamps | Security monitoring, session management | Legitimate interest (Art. 6(1)(f) GDPR) |
| IP address | Security monitoring, abuse prevention | Legitimate interest (Art. 6(1)(f) GDPR) |
| User agent | Device identification for session management | Legitimate interest (Art. 6(1)(f) GDPR) |
| Session tokens | Maintaining authenticated sessions | Contract performance (Art. 6(1)(b) GDPR) |

### 3.3 Authorization Data

| Data | Purpose | Legal Basis |
|------|---------|-------------|
| Organization membership | Access control | Contract performance (Art. 6(1)(b) GDPR) |
| Project roles and grants | Role-based access control for connected applications | Contract performance (Art. 6(1)(b) GDPR) |
| OAuth/OIDC consent records | Recording which applications you authorized | Consent (Art. 6(1)(a) GDPR) |

---

## 4. How We Use Your Data

### 4.1 Providing the Service

- Creating and maintaining your account
- Authenticating your identity
- Managing access to connected applications via OAuth2/OIDC
- Enforcing role-based access policies

### 4.2 Security

- Detecting unauthorized access attempts
- Preventing brute-force and credential-stuffing attacks
- Maintaining audit logs for security incident investigation

### 4.3 What We Do NOT Do

- We do NOT sell or share your data with third parties
- We do NOT use your data for advertising
- We do NOT use third-party analytics or tracking services
- We do NOT profile you for purposes beyond providing our services

---

## 5. Data Storage and Security

### 5.1 Where Your Data Is Stored

All data is stored within **{{ (ds "config").data.location }}** on infrastructure operated by us.
{{ if (ds "config").hosting_provider.name }}
**Data Processor:**

| Provider | Purpose | Location |
|----------|---------|----------|
| {{ (ds "config").hosting_provider.name }} | {{ (ds "config").hosting_provider.purpose }} | {{ (ds "config").hosting_provider.location }} |

We do not use any additional third-party cloud services, analytics providers, or external data processors beyond the hosting provider listed above.
{{ end }}
### 5.2 Security Measures

- **Encryption in transit**: All connections use TLS encryption
- **Password hashing**: Passwords are stored using strong one-way hashing
- **Access controls**: Administrative access is restricted and audited
- **Audit logging**: Authentication events are logged for security monitoring

---

## 6. Data Retention

| Data Type | Retention Period |
|-----------|-----------------|
| Account data | Until account deletion |
| Authentication logs | 90 days |
| Session data | Until session expiry or logout |
| Audit logs | 12 months |

When your account is deleted, all associated personal data is permanently removed.

---

## 7. Your Rights

Under GDPR, you have the following rights:

### 7.1 Right of Access (Art. 15 GDPR)

You can request a copy of all personal data we hold about you.

### 7.2 Right to Rectification (Art. 16 GDPR)

You can correct any inaccurate personal data via your account settings or by contacting us.

### 7.3 Right to Erasure (Art. 17 GDPR)

You can request deletion of your account and all associated data.

### 7.4 Right to Restrict Processing (Art. 18 GDPR)

You can request that we limit how we process your data.

### 7.5 Right to Data Portability (Art. 20 GDPR)

You can request your data in a machine-readable format.

### 7.6 Right to Object (Art. 21 GDPR)

You can object to processing based on legitimate interests.

### 7.7 Right to Withdraw Consent (Art. 7(3) GDPR)

Where processing is based on consent (e.g. OAuth application authorizations), you can withdraw consent at any time. Withdrawal does not affect the lawfulness of processing before withdrawal.

### 7.8 Right to Lodge a Complaint

You have the right to lodge a complaint with a data protection supervisory authority.{{ if (ds "config").supervisory_authority.name }}

The relevant authority is:

**{{ (ds "config").supervisory_authority.name }}**
{{ if (ds "config").supervisory_authority.address }}{{ (ds "config").supervisory_authority.address }}
{{ end }}{{ if (ds "config").supervisory_authority.website }}{{ (ds "config").supervisory_authority.website }}
{{ end }}{{ end }}

To exercise any of these rights, contact us at {{ (ds "config").contact.email }}. We will respond within 30 days.

---

## 8. Third-Party Applications

When you authorize a third-party application via OAuth2/OIDC, that application receives only the data you explicitly consent to share (such as your email address and name). Each application has its own privacy policy governing how it uses your data.

You can review and revoke application authorizations at any time through your account settings.

---

## 9. Changes to This Privacy Policy

We may update this privacy policy from time to time. Significant changes will be communicated through the service. The "Last updated" date at the top indicates when the policy was last revised.

---

## 10. Contact Us

For questions about this privacy policy or to exercise your rights:

**Email**: {{ (ds "config").contact.email }}
{{ if (ds "config").organization.address }}**Mail**: {{ (ds "config").organization.name }}, {{ (ds "config").organization.address }}
{{ end }}
We will respond to your request within 30 days, or inform you if we need additional time (up to 90 days for complex requests).
