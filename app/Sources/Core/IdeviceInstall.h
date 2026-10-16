// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
// The few idevice C entry points the on-device installer calls. They live in Vendor/StikJIT.xcframework (the framework exports idevice's whole
// C interface but ships no header), so they are declared here by hand. Signatures follow idevice's ffi/ sources (jkcoxson/idevice), the same ones
// StikDebug calls; ownership rules are in IdeviceInstall.swift.
#ifndef IdeviceInstall_h
#define IdeviceInstall_h

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <sys/socket.h>

// Every call returns NULL on success, or an error to read and then free with idevice_error_free.
typedef struct IdeviceFfiError {
    int32_t code;
    int32_t sub_code;      // absent in older builds; `message` sits at the same offset either way
    const char *message;
} IdeviceFfiError;

typedef struct RpPairingFileHandle RpPairingFileHandle;
typedef struct AdapterHandle AdapterHandle;
typedef struct RsdHandshakeHandle RsdHandshakeHandle;
typedef struct AfcClientHandle AfcClientHandle;
typedef struct AfcFileHandle AfcFileHandle;
typedef struct InstallationProxyClientHandle InstallationProxyClientHandle;

void idevice_error_free(IdeviceFfiError *err);

IdeviceFfiError *rp_pairing_file_read(const char *path, RpPairingFileHandle **out);
void rp_pairing_file_free(RpPairingFileHandle *handle);

IdeviceFfiError *tunnel_create_rppairing(const struct sockaddr *addr, socklen_t addr_len, const char *hostname,
                                         RpPairingFileHandle *pairing_file,
                                         const char *(*pin_callback)(void *context), void *pin_context,
                                         AdapterHandle **out_adapter, RsdHandshakeHandle **out_handshake);
IdeviceFfiError *adapter_close(AdapterHandle *handle);
void adapter_free(AdapterHandle *handle);
void rsd_handshake_free(RsdHandshakeHandle *handle);

IdeviceFfiError *afc_client_connect_rsd(AdapterHandle *provider, RsdHandshakeHandle *handshake, AfcClientHandle **client);
void afc_client_free(AfcClientHandle *handle);
IdeviceFfiError *afc_make_directory(AfcClientHandle *client, const char *path);
IdeviceFfiError *afc_remove_path(AfcClientHandle *client, const char *path);
// mode: 1 read-only, 2 read/write, 3 write-only (create/truncate), 4 write, 5 append, 6 read/append
IdeviceFfiError *afc_file_open(AfcClientHandle *client, const char *path, int32_t mode, AfcFileHandle **handle);
IdeviceFfiError *afc_file_write(AfcFileHandle *handle, const uint8_t *data, size_t length);
// whence: 0 from the start, 1 from here, 2 from the end; new_position must not be NULL.
IdeviceFfiError *afc_file_seek(AfcFileHandle *handle, int64_t offset, int32_t whence, int64_t *new_position);
IdeviceFfiError *afc_file_close(AfcFileHandle *handle);

IdeviceFfiError *installation_proxy_connect_rsd(AdapterHandle *provider, RsdHandshakeHandle *handshake, InstallationProxyClientHandle **client);
void installation_proxy_client_free(InstallationProxyClientHandle *handle);
// `options` is a libplist dictionary or NULL.
IdeviceFfiError *installation_proxy_install_with_callback(InstallationProxyClientHandle *client, const char *package_path, void *options,
                                                          void (*callback)(uint64_t progress, void *context), void *context);

IdeviceFfiError *installation_proxy_upgrade_with_callback(InstallationProxyClientHandle *client, const char *package_path, void *options,
                                                          void (*callback)(uint64_t progress, void *context), void *context);

// libplist, exported by the same framework: the options dictionary of an install ({"PackageType": "Developer"}).
typedef void *plist_t;
plist_t plist_new_dict(void);
plist_t plist_new_string(const char *val);
void plist_dict_set_item(plist_t node, const char *key, plist_t item);

#endif
