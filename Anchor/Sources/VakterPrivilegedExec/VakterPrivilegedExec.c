#include "VakterPrivilegedExec.h"

#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>
#include <string.h>

// Return codes — kept stable; Swift's SleepDisabler maps these to a
// typed enum.
//
//   0   success
//  -1   AuthorizationCreate failed (catastrophic)
//  -2   user cancelled the password / Touch ID prompt
//  -3   AuthorizationCopyRights failed for another reason
//       (interaction not allowed, max retries, etc.)
//  -4   AuthorizationExecuteWithPrivileges failed (rare)
int anchor_run_pmset_admin(int disable) {
    AuthorizationRef authRef = NULL;
    OSStatus status = AuthorizationCreate(NULL, NULL,
                                          kAuthorizationFlagDefaults,
                                          &authRef);
    if (status != errAuthorizationSuccess || authRef == NULL) {
        return -1;
    }

    // Friendly prompt body. macOS still pulls the dialog *title* from
    // the calling binary's name (CFBundleName / executable name), so
    // we can't override that here — but at least the body explains why
    // the prompt exists and how to make it stop appearing.
    const char *promptText =
        "Vakter needs admin access once to disable system sleep while "
        "armed, so the alarm can fire on a closed lid. Approve Vakter "
        "in System Settings → Login Items & Extensions and you "
        "will not see this prompt again.";

    AuthorizationItem envItems[1] = {
        {
            .name = kAuthorizationEnvironmentPrompt,
            .valueLength = strlen(promptText),
            .value = (void *)promptText,
            .flags = 0
        }
    };
    AuthorizationEnvironment environment = {
        .count = 1, .items = envItems
    };

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

    status = AuthorizationCopyRights(authRef, &rights, &environment,
                                     flags, NULL);
    if (status != errAuthorizationSuccess) {
        AuthorizationFree(authRef, kAuthorizationFlagDestroyRights);
        if (status == errAuthorizationCanceled) {
            // User explicitly cancelled — the caller should NOT proceed
            // with arming.
            return -2;
        }
        return -3;
    }

    char *value = disable ? "1" : "0";
    char *args[] = { "-a", "disablesleep", value, NULL };

    // AuthorizationExecuteWithPrivileges is deprecated since 10.7 but still
    // functional in modern macOS. The proper long-term replacement is
    // SMJobBless / SMAppService.daemon — already wired as the primary path.
    status = AuthorizationExecuteWithPrivileges(authRef,
                                                "/usr/bin/pmset",
                                                kAuthorizationFlagDefaults,
                                                args,
                                                NULL);

    AuthorizationFree(authRef, kAuthorizationFlagDestroyRights);
    return (status == errAuthorizationSuccess) ? 0 : -4;
}
