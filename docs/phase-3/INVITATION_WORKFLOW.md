# Invitation Workflow

1. An authorised admin (`staff.invite`) calls `POST /staff/{id}/invite` (or `POST /invitations`) with role and branch scope.
2. The server creates `tenants/{t}/invitations/{id}` with a **256-bit random token** (`ecinv_…`). **Only the SHA-256 hash is stored**; the plaintext is returned once, in the response, to the inviting admin.
3. **Delivery:** no e-mail/SMS provider is configured. The response reports `delivery: "not_configured"` and the admin shares the link manually. Delivery is **not faked** (blocker TD-28).
4. TTL 7 days. `resend` rotates the secret (old link dies); `revoke` is immediate.
5. **Acceptance** (`POST /invitations/accept {token}`, authenticated user): the server hashes the token, finds the invitation by collection-group query on `tokenHash`, and inside one transaction checks: pending, unexpired, account active, **e-mail verified and equal to the invited e-mail**; then marks it accepted and creates the membership (+ links doctor/staff profile). A second use fails. Any failure returns one generic message (no enumeration of why).
6. Rate limits: invitation creation 30/h, acceptance 10/h per user.
7. A user already belonging to another clinic can accept; memberships are independent per tenant.

Security tests: wrong e-mail, unverified e-mail, expired, revoked, reused, rotated token, token-as-id guess, cross-tenant — all in `staff_invitation_test.dart`.
