# modules/

One folder per business domain, added phase by phase (auth, clinics, patients,
appointments, ...). Each module owns its routes, request validation, service
(business rules), repository interface and models:

```
modules/<domain>/
  <domain>_routes.dart      # Router mounted under /api/v1/<domain>
  <domain>_service.dart     # business rules + authorization policy calls
  <domain>_repository.dart  # interface; Firestore implementation in infrastructure/
  models/
```

Phase 0 contains no modules.
