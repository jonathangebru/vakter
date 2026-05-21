#ifndef ANCHOR_PRIVILEGED_EXEC_H
#define ANCHOR_PRIVILEGED_EXEC_H

/// Acquires `system.privilege.admin` via `AuthorizationCopyRights` (which
/// presents the modern system auth dialog — Touch ID-capable on supported
/// Macs), then runs `/usr/bin/pmset -a disablesleep <1|0>` as root.
///
/// Returns 0 on success, non-zero on failure. Specific failures:
///    -1  AuthorizationCreate failed
///    -2  AuthorizationCopyRights failed (often: user canceled the prompt)
///    -3  AuthorizationExecuteWithPrivileges failed
///
/// This file exists because `AuthorizationExecuteWithPrivileges` is
/// explicitly marked **unavailable in Swift** by Apple's overlay, even
/// though it remains functional in C. Bridging through this tiny C
/// target sidesteps that restriction.
int anchor_run_pmset_admin(int disable);

#endif /* ANCHOR_PRIVILEGED_EXEC_H */
