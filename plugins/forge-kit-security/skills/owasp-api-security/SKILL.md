---
name: owasp-api-security
description: OWASP API Security Top 10 testing patterns, injection payloads, auth bypass vectors, and security test generation for REST APIs. Use when writing security tests, reviewing API endpoints for vulnerabilities, or auditing input validation.
---

<!-- owasp-api-security-version: 3 -->

# OWASP API Security Testing

Comprehensive security testing knowledge base for REST APIs, aligned with OWASP API Security Top 10:2023 and OWASP ASVS 5.0.

The code examples below are TypeScript illustrations (Fastify-style `app.inject`, Vitest). Translate them
to the project's own framework, validator and test runner; the endpoints, field names and codes are
placeholders.

## When to Use This Skill

- Writing security tests for API endpoints
- Reviewing endpoints for OWASP vulnerabilities
- Generating injection/fuzzing payloads for test suites
- Auditing authentication and authorization logic
- Validating input sanitization and output encoding
- Assessing rate limiting and resource exhaustion protections

## OWASP API Security Top 10:2023

### API1 - Broken Object Level Authorization (BOLA / IDOR)

**What:** User A can access/modify User B's resources by manipulating IDs.

**Test patterns:**
```typescript
// Access another user's resource
const res = await app.inject({
  method: 'GET',
  url: '/users/OTHER_USER_ID',
  headers: { cookie: userASession },
})
expect(res.statusCode).toBe(403) // or 404 - never 200

// Modify another user's resource
const res = await app.inject({
  method: 'PUT',
  url: '/resources/OTHER_USER_RESOURCE_ID',
  headers: { cookie: userASession },
  payload: { name: 'hijacked' },
})
expect(res.statusCode).toBe(403)
```

**Checklist:**
- [ ] Every endpoint with `:id` params verified against session user
- [ ] Enumerable IDs (sequential integers) replaced with CUIDs
- [ ] List endpoints only return resources owned by/shared with caller

### API2 - Broken Authentication

**Test patterns:**
```typescript
// No auth header
const res = await app.inject({ method: 'GET', url: '/users/me' })
expect(res.statusCode).toBe(401)

// Expired/invalid session
const res = await app.inject({
  method: 'GET',
  url: '/users/me',
  headers: { cookie: 'session_token=expired123' },
})
expect(res.statusCode).toBe(401)

// Malformed auth header
const res = await app.inject({
  method: 'GET',
  url: '/users/me',
  headers: { authorization: 'Bearer <script>alert(1)</script>' },
})
expect(res.statusCode).toBe(401)
```

### API3 - Broken Object Property Level Authorization

**Test patterns:**
- Mass assignment: send extra fields not in the request schema → must be stripped
- Response filtering: sensitive fields (passwordHash, tokens) never in response
```typescript
const res = await app.inject({
  method: 'PUT',
  url: '/users/me',
  headers: { cookie: session },
  payload: { tier: 'premium', role: 'admin' },
})
// Verify tier/role unchanged in DB
```

### API4 - Unrestricted Resource Consumption

**Test patterns:**
- Oversized payloads (>1MB body)
- Pagination abuse (perPage=999999)
- Rapid-fire requests exceeding rate limits
```typescript
// Oversized payload
const res = await app.inject({
  method: 'POST',
  url: '/items',
  headers: { cookie: session },
  payload: { name: 'x'.repeat(1_000_000) },
})
expect(res.statusCode).toBe(400) // or 413
```

### API5 - Broken Function Level Authorization

**Test patterns:**
- A caller without the required plan or role accessing a gated endpoint
- Regular user accessing admin endpoints
```typescript
const res = await app.inject({
  method: 'POST',
  url: '/gated-items',
  headers: { cookie: unprivilegedSession },
  payload: validPayload,
})
expect(res.statusCode).toBe(403)
expect(res.json().code).toBe('PLAN_REQUIRED') // the project's own code
```

### API6 - Unrestricted Access to Sensitive Business Flows

- Rate limiting on flows that trigger notifications, invitations or other costly side effects
- Per-user caps on actions that are cheap to script and expensive to absorb (signups, invites, exports)
- Abuse prevention on any flow whose automated use would harm the business or other users

### API7 - Server-Side Request Forgery (SSRF)

- SSRF applies whenever users supply URLs (webhooks, avatars, imports, link previews)
- Validate any user-supplied URL against an allowlist and block private and link-local address ranges

### API8 - Security Misconfiguration

**Test patterns:**
```typescript
// CORS: reject disallowed origins
// Stack traces: never exposed in error responses
const res = await app.inject({
  method: 'POST',
  url: '/nonexistent',
  headers: { cookie: session },
})
expect(res.json()).not.toHaveProperty('stack')
expect(res.json()).toHaveProperty('error')

// HTTP methods: reject unsupported methods
const res = await app.inject({ method: 'TRACE', url: '/items' })
expect([404, 405]).toContain(res.statusCode)
```

### API9 - Improper Inventory Management

- All endpoints documented and tested
- No shadow/debug endpoints in production
- Deprecated endpoints return proper status codes

### API10 - Unsafe Consumption of APIs

- Webhook signature verification (payment, identity and platform providers)
- External API response validation before processing

## Injection Payload Library

### SQL Injection (via validation-bypass attempts)
```typescript
const sqlPayloads = [
  "' OR '1'='1",
  "'; DROP TABLE users; --",
  "1; SELECT * FROM user --",
  "' UNION SELECT null,null,null --",
  "admin'--",
  "1' AND 1=1 --",
  "' OR 1=1 LIMIT 1 --",
]
```

### XSS Payloads (stored XSS via API)
```typescript
const xssPayloads = [
  '<script>alert(1)</script>',
  '<img src=x onerror=alert(1)>',
  'javascript:alert(1)',
  '<svg onload=alert(1)>',
  '"><script>alert(document.cookie)</script>',
  "'-alert(1)-'",
  '<iframe src="javascript:alert(1)">',
]
```

### Command Injection
```typescript
const cmdPayloads = [
  '; ls -la',
  '| cat /etc/passwd',
  '$(whoami)',
  '`id`',
  '& ping -c 1 attacker.com',
  '\n/bin/sh',
]
```

### NoSQL Injection
```typescript
const nosqlPayloads = [
  '{"$gt": ""}',
  '{"$ne": null}',
  '{"$where": "sleep(5000)"}',
]
```

### Path Traversal
```typescript
const pathPayloads = [
  '../../../etc/passwd',
  '..\\..\\..\\windows\\system32',
  '%2e%2e%2f%2e%2e%2f',
  '....//....//....//etc/passwd',
]
```

## Security Test Template

```typescript
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { buildApp } from '../../app'
import { createTestUser } from '../helpers/seed'
import type { FastifyInstance } from 'fastify'

describe('ENDPOINT security', () => {
  let app: FastifyInstance
  let user: TestUser
  let otherUser: TestUser

  beforeAll(async () => {
    app = await buildApp()
    user = await createTestUser(app)
    otherUser = await createTestUser(app)
  })

  afterAll(async () => { await app.close() })

  describe('authentication', () => {
    it('rejects unauthenticated requests', async () => {
      const res = await app.inject({ method: 'METHOD', url: '/path' })
      expect(res.statusCode).toBe(401)
    })

    it('rejects invalid session tokens', async () => {
      const res = await app.inject({
        method: 'METHOD',
        url: '/path',
        headers: { cookie: 'session_token=invalid' },
      })
      expect(res.statusCode).toBe(401)
    })
  })

  describe('authorization (IDOR)', () => {
    it('cannot access other users resources', async () => {
      const res = await app.inject({
        method: 'GET',
        url: `/resource/${otherUser.resourceId}`,
        headers: { cookie: user.sessionCookie },
      })
      expect([403, 404]).toContain(res.statusCode)
    })
  })

  describe('input validation', () => {
    it('rejects empty body', async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/path',
        headers: { cookie: user.sessionCookie },
      })
      expect(res.statusCode).toBe(400)
    })

    it('rejects injection payloads', async () => {
      for (const payload of sqlPayloads) {
        const res = await app.inject({
          method: 'POST',
          url: '/path',
          headers: { cookie: user.sessionCookie },
          payload: { field: payload },
        })
        expect(res.statusCode).not.toBe(500)
      }
    })
  })

  describe('error response format', () => {
    it('returns the project error shape without stack traces', async () => {
      const res = await app.inject({
        method: 'POST',
        url: '/path',
        headers: { cookie: user.sessionCookie },
        payload: {},
      })
      if (res.statusCode >= 400) {
        const body = res.json()
        expect(body).toHaveProperty('error')
        expect(body).not.toHaveProperty('stack')
        expect(body).not.toHaveProperty('stackTrace')
      }
    })
  })
})
```
