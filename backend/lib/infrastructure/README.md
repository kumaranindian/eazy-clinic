# infrastructure/

Adapters to external systems: Firebase Admin (Firestore, Auth, Storage, FCM),
Razorpay, notification providers. Added from Phase 1 onward.

Rules:
- Modules depend on small interfaces defined in `modules/`, implemented here, so
  business logic can be unit-tested with fakes.
- Credentials come from the hosting environment, never from the repository.
