# Branch-Scoped Access (Module G)

A membership has `allBranches: true` **or** an explicit `branchIds` list (server-side record). Phase 2 owner memberships (`branchIds: []`) are read as all-branches.

`TenantContext` is built per request from the caller's verified membership; the `X-Tenant-Id` header is only a *selector* validated against the user's own memberships. `BranchScope` then:
- filters lists to the allowed branches;
- answers 404 for a resource outside the scope (existence is not disclosed);
- rejects creating/assigning outside the scope.

The branch chosen in the web branch selector is a display hint only and grants nothing. Changing another member's branches requires `staff.assign_branch`, cannot target oneself, and cannot widen beyond what the actor may grant.
