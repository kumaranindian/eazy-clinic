# firebase/

Security rules and index definitions for the three Firebase projects
(dev, staging, production). **Phase 0 contains deny-all baselines only.**

- `firestore.rules`, `storage.rules`: deny all client access. Data is accessed
  through the backend (Firebase Admin SDK).
- `firestore.indexes.json`: empty. Indexes are added together with the queries
  that need them (see docs/database/DATABASE_SCHEMA.md for planned indexes).
- `.firebaserc.example`: copy to `.firebaserc` (git-ignored) and fill in your
  project IDs.

Nothing here has been deployed. Deploying to staging or production requires
explicit approval (CLAUDE.md, section 19).
