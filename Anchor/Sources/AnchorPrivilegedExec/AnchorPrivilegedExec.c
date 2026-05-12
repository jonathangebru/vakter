#include "AnchorPrivilegedExec.h"

#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>

int anchor_run_pmset_admin(int disable) {
    AuthorizationRef authRef = NULL;
    OSStatus status = AuthorizationCreate(NULL, NULL,
                                          kAuthorizationFlagDefaults,
                                          &authRef);
    if (status != errAuthorizationSuccess || authRef == NULL) {
        return -1;
    }

    AuthorizationItem item = {
        .name = "system.privilege.admin",
        .valueLength = 0,
        .value = NULL,
        .flags = 0
    };
    AuthorizationRights rights = { .count = 1, .items = &item };
    AuthorizationFlags flags = (kAuthorizationFlagInteractionAllowed |
                                kAuthorizationFlagExtendRights      |
                                kAuthorizationFlagPreAuthorize);

    status = AuthorizationCopyRights(authRef, &rights, NULL, flags, NULL);
    if (status != errAuthorizationSuccess) {
        AuthorizationFree(authRef, kAuthorizationFlagDestroyRights);
        return -2;
    }

    char *value = disable ? "1" : "0";
    char *args[] = { "-a", "disablesleep", value, NULL };

    // AuthorizationExecuteWithPrivileges is deprecated since 10.7 but still
    // functional in modern macOS. The proper long-term replacement is
    // SMJobBless / SMAppService.daemon — sequenced for v1.5+.
    status = AuthorizationExecuteWithPrivileges(authRef,
                                                "/usr/bin/pmset",
                                                kAuthorizationFlagDefaults,
                                                args,
                                                NULL);

    AuthorizationFree(authRef, kAuthorizationFlagDestroyRights);
    return (status == errAuthorizationSuccess) ? 0 : -3;
}
