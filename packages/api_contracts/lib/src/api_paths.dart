/// Versioned API base path. All business endpoints live under this prefix.
const String apiV1Prefix = '/api/v1';

/// Unversioned infrastructure endpoint (no authentication, no business data).
const String healthPath = '/health';

/// Header carrying the per-request correlation id.
const String requestIdHeader = 'x-request-id';

/// Header carrying the client-generated idempotency key for payment and
/// booking operations.
const String idempotencyKeyHeader = 'idempotency-key';
