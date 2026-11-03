# environments/

Configuration templates for the three isolated environments. See
docs/deployment/ENVIRONMENT_STRATEGY.md.

| File | Used by | How |
|---|---|---|
| `<env>/backend.env.example` | backend | Export as environment variables (`scripts/run_backend.sh <env>` loads `backend.env`). |
| `<env>/app.example.json` | Flutter apps | `flutter run --dart-define-from-file=../../environments/<env>/app.json` |

Copy `*.example.*` to the same name without `.example` and fill in real values.
Real files are git-ignored. **Only placeholders belong in this repository.**
The Flutter client files contain no secrets (the API URL and, from Phase 1,
Firebase *client* identifiers are public by design). Service-account keys and
Razorpay secrets never go in the apps.
