// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
#include "SampleProfiler.h"
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/resource.h>
#include <unistd.h>
#include <notify.h>
#include <CoreFoundation/CoreFoundation.h>

// The engine's own pieces: the TLS key of the Windows TEB, and the resolver that turns a host pc inside a translated block into the x86 rip (it reads the host-pc table FEX
// appends to every block; fault-safe). Both are linked into the app from libntdll_unix.a.
extern pthread_key_t ios_teb_tls_key;
extern uint64_t ios_native_rip_from_hostpc(uint64_t block_begin, uint64_t host_pc, const char **why);
// The graphics layer's per-render-pass GPU timer (dxmt winemetal_unix.c, patch 0144): on while the profile samples, its table is logged at the end.
extern void madeira_passprof_start(void);
extern void madeira_passprof_dump(double seconds);

#define MAX_THREADS 512
#define MAX_MODS 200
#define MAX_MAPS 6

typedef struct { uint64_t pc, lr, rip, cr[4], fr[3]; uint32_t th; uint8_t kind; } Sample;   /* kind 0 host, 1 translated x86 (rip), 2 native code of a module copy in the JIT pool (rip = pc) */
typedef struct { uint64_t tid, teb; pthread_t pt; char name[40]; uint32_t ticks, run, guest; } ThreadRow;

typedef struct { uint32_t rva; char name[48]; } Export;
typedef struct {
    uint64_t base, size; char name[40];
    int pe_done; uint32_t *pd; uint32_t npd; Export *ex; uint32_t nex;
} Mod;
typedef struct { uint64_t peb; int n; Mod m[MAX_MODS]; } ModMap;

static struct {
    double seconds; int hz; void (*logger)(const char *);
    Sample *samples; size_t cap, n;
    ThreadRow rows[MAX_THREADS]; int nrows;
    uint32_t no_bb, bb_unresolved;
    long tsd_off;
    volatile int running, phase;
    double t0;
} g;
static ModMap maps[MAX_MAPS];
#define MAX_NAT 32
static Mod natmods[MAX_NAT];
static int nnat;
static int nmaps;

static void say(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void say(const char *fmt, ...) {
    char line[600];
    va_list ap; va_start(ap, fmt); vsnprintf(line, sizeof line, fmt, ap); va_end(ap);
    if (g.logger) g.logger(line);
    else { fputs(line, stderr); fputc('\n', stderr); }   /* the engine's log file takes the process's stderr */
}

static int rd(uint64_t a, void *o, size_t n) {
    vm_size_t got = 0;
    return a > 0x10000 && vm_read_overwrite(mach_task_self(), (vm_address_t)a, n, (vm_address_t)o, &got) == KERN_SUCCESS && got == n;
}

/// The TEB sits in the pthread's TSD slot ios_teb_tls_key; the TSD array's offset inside struct pthread is found by calibration (as the engine's own sampler does).
static void calibrate(void) {
    pthread_key_t k; char *base = (char *)pthread_self();
    g.tsd_off = -1;
    if (pthread_key_create(&k, NULL)) return;
    pthread_setspecific(k, (void *)0x5a5a1234abcdULL);
    for (long off = 0; off < 8192; off += 8) {
        uint64_t v = 0;
        if (rd((uint64_t)(uintptr_t)base + off + (uint64_t)k * 8, &v, 8) && v == 0x5a5a1234abcdULL) { g.tsd_off = off; break; }
    }
    pthread_setspecific(k, NULL); pthread_key_delete(k);
}
static uint64_t teb_of(pthread_t pt) {
    uint64_t v = 0;
    if (g.tsd_off < 0 || !pt || !ios_teb_tls_key) return 0;
    rd((uint64_t)(uintptr_t)pt + g.tsd_off + (uint64_t)ios_teb_tls_key * 8, &v, 8);
    return (v & 0xfff) ? 0 : v;
}

// ---- sampling (nothing between thread_suspend and thread_resume allocates or takes a lock) ----

static int row_for(thread_act_t t) {
    thread_identifier_info_data_t id; mach_msg_type_number_t cnt = THREAD_IDENTIFIER_INFO_COUNT;
    if (thread_info(t, THREAD_IDENTIFIER_INFO, (thread_info_t)&id, &cnt) != KERN_SUCCESS) return -1;
    for (int i = 0; i < g.nrows; i++) if (g.rows[i].tid == id.thread_id) return i;
    if (g.nrows >= MAX_THREADS) return -1;
    ThreadRow *r = &g.rows[g.nrows];
    memset(r, 0, sizeof *r);
    r->tid = id.thread_id;
    r->pt = pthread_from_mach_thread_np(t);
    if (r->pt) pthread_getname_np(r->pt, r->name, sizeof r->name);
    r->teb = teb_of(r->pt);
    return g.nrows++;
}

// ---- modules of the game's process: loader list, PE exports and unwind table ----

static ModMap *map_for_teb(uint64_t teb) {
    uint64_t peb = 0, ldr = 0, head, cur;
    if (!teb || !rd(teb + 0x60, &peb, 8) || !peb) return NULL;
    for (int i = 0; i < nmaps; i++) if (maps[i].peb == peb) return &maps[i];
    if (nmaps >= MAX_MAPS || !rd(peb + 0x18, &ldr, 8) || !ldr) return NULL;
    ModMap *mp = &maps[nmaps];
    memset(mp, 0, sizeof *mp); mp->peb = peb;
    head = ldr + 0x10;
    if (!rd(head, &cur, 8)) return NULL;
    for (int guard = 0; cur && cur != head && guard < 400 && mp->n < MAX_MODS; guard++) {
        uint64_t base = 0, buf = 0, next = 0; uint32_t size = 0; uint16_t len = 0, w[40];
        if (!rd(cur + 0x30, &base, 8) || !rd(cur + 0x40, &size, 4) || !rd(cur + 0x58, &len, 2) || !rd(cur + 0x60, &buf, 8)) break;
        if (base && size) {
            Mod *m = &mp->m[mp->n++];
            m->base = base; m->size = size;
            len /= 2; if (len > 39) len = 39;
            if (len && rd(buf, w, len * 2)) { for (int k = 0; k < len; k++) m->name[k] = w[k] < 128 ? (char)w[k] : '?'; m->name[len] = 0; }
            else strcpy(m->name, "?");
        }
        if (!rd(cur, &next, 8)) break;
        cur = next;
    }
    nmaps++;
    return mp;
}

static int cmp_export(const void *a, const void *b) { uint32_t x = ((const Export *)a)->rva, y = ((const Export *)b)->rva; return x < y ? -1 : x > y; }

static void pe_load(Mod *m) {
    if (m->pe_done) return;
    m->pe_done = 1;
    uint32_t lfanew = 0; uint16_t magic = 0; uint32_t dd[8] = {0};
    if (!rd(m->base + 0x3c, &lfanew, 4) || lfanew > 0x1000) return;
    uint64_t nt = m->base + lfanew;
    if (!rd(nt + 0x18, &magic, 2) || magic != 0x20b) return;
    if (!rd(nt + 0x88, dd, sizeof dd)) return;   // data directories 0 (export) and 1 (import, unused) , 2, 3 (exception) = dd[6], dd[7]
    uint32_t expRva = dd[0], expSz = dd[1], excRva = dd[6], excSz = dd[7];
    if (excRva && excSz && excSz < (96u << 20)) {
        uint32_t *pd = malloc(excSz);
        if (pd && rd(m->base + excRva, pd, excSz)) { m->pd = pd; m->npd = excSz / 12; } else free(pd);
    }
    if (expRva && expSz >= 40) {
        uint32_t ed[10];
        if (rd(m->base + expRva, ed, sizeof ed)) {
            uint32_t nn = ed[6], fn = ed[7], nm = ed[8], on = ed[9], nf = ed[5];
            if (nn && nn < 40000 && nf < 80000) {
                uint32_t *names = malloc(nn * 4); uint16_t *ords = malloc(nn * 2); uint32_t *fns = malloc((nf ? nf : 1) * 4);
                Export *ex = malloc(nn * sizeof(Export));
                if (names && ords && fns && ex && rd(m->base + nm, names, nn * 4) && rd(m->base + on, ords, nn * 2) && rd(m->base + fn, fns, nf * 4)) {
                    uint32_t k = 0;
                    for (uint32_t i = 0; i < nn; i++) {
                        if (ords[i] >= nf) continue;
                        char s[48] = {0};
                        vm_size_t got = 0;
                        vm_read_overwrite(mach_task_self(), (vm_address_t)(m->base + names[i]), 47, (vm_address_t)s, &got);
                        ex[k].rva = fns[ords[i]]; strncpy(ex[k].name, s, 47); ex[k].name[47] = 0; k++;
                    }
                    qsort(ex, k, sizeof(Export), cmp_export);
                    m->ex = ex; m->nex = k; ex = NULL;
                }
                free(names); free(ords); free(fns); free(ex);
            }
        }
    }
}

// The function (unwind-table entry) that holds rva; 0 when no entry covers it (a leaf function has none).
static int func_of(Mod *m, uint32_t rva, uint32_t *begin, uint32_t *end) {
    pe_load(m);
    if (!m->pd || !m->npd) return 0;
    uint32_t lo = 0, hi = m->npd;
    while (lo < hi) { uint32_t mid = (lo + hi) / 2; if (m->pd[mid * 3] <= rva) lo = mid + 1; else hi = mid; }
    if (!lo) return 0;
    uint32_t *e = &m->pd[(lo - 1) * 3];
    if (rva >= e[1]) return 0;
    uint32_t unwind = e[2];
    if (!(unwind & 1)) {   // a chained entry (a cold part of a bigger function) belongs to its parent: follow one level
        uint8_t hdr[4];
        if (rd(m->base + unwind, hdr, 4) && (hdr[0] >> 3) & 4) {
            uint32_t parent[3]; uint32_t off = 4 + ((hdr[2] + 1u) & ~1u) * 2;
            if (rd(m->base + unwind + off, parent, 12) && parent[0] < parent[1] && parent[1] <= m->size) { *begin = parent[0]; *end = parent[1]; return 1; }
        }
    }
    *begin = e[0]; *end = e[1];
    return 1;
}

static const char *export_at(Mod *m, uint32_t rva) {
    if (!m->ex) return NULL;
    Export key = { rva, {0} };
    Export *r = bsearch(&key, m->ex, m->nex, sizeof(Export), cmp_export);
    return r ? r->name : NULL;
}

static int nearest_export(Mod *m, uint32_t rva, uint32_t *exrva, const char **name);

// A guest rip as one 64-bit key: module number + function begin (or a 256-byte bucket where no unwind entry covers it); 0 module = anonymous (a 64 KB bucket).
#define KEY_MOD(k) ((unsigned)((k) >> 48))
#define KEY_LOW(k) ((k) & 0xffffffffffffull)
static uint64_t key_for_native(uint64_t pc) {
    for (int i = 0; i < nnat; i++) {
        Mod *m = &natmods[i];
        if (pc >= m->base && pc < m->base + m->size) {
            uint32_t rva = (uint32_t)(pc - m->base), ex; const char *nm;
            if (nearest_export(m, rva, &ex, &nm)) return ((uint64_t)(0x100 + i) << 48) | ex;
            return ((uint64_t)(0x100 + i) << 48) | (1ull << 40) | (rva & ~0xffu);   /* 256-byte pieces: enough to name the function from the module's symbol table offline */
        }
    }
    return 0;
}
static uint64_t key_for(ModMap *mp, uint64_t rip, uint32_t *size_out) {
    *size_out = 0;
    if (mp) for (int i = 0; i < mp->n; i++) {
        Mod *m = &mp->m[i];
        if (rip >= m->base && rip < m->base + m->size) {
            uint32_t rva = (uint32_t)(rip - m->base), b, e;
            if (func_of(m, rva, &b, &e)) { *size_out = e - b; return ((uint64_t)(i + 1) << 48) | b; }
            return ((uint64_t)(i + 1) << 48) | (1ull << 40) | (rva & ~0xffu);
        }
    }
    return (rip >> 16) & 0xffffffffffull;
}
static void key_name(ModMap *mp, uint64_t key, char *out, size_t n) {
    unsigned mi = KEY_MOD(key);
    if (mi >= 0x100 && mi - 0x100 < (unsigned)nnat) {   // native ARM64EC code of a module copy
        Mod *m = &natmods[mi - 0x100]; uint64_t low = KEY_LOW(key);
        if (low & (1ull << 40)) snprintf(out, n, "%s native code +0x%llx.. (256 B, no export nearby)", m->name, (unsigned long long)(low & ~(1ull << 40)));
        else { const char *ex = export_at(m, (uint32_t)low); snprintf(out, n, "%s!%s.. native (the export it starts at or follows)", m->name, ex ? ex : "?"); }
        return;
    }
    if (!mi || !mp || mi > (unsigned)mp->n) { snprintf(out, n, "code outside any module at 0x%llx (Mono JIT or packed)", (unsigned long long)(KEY_LOW(key) << 16)); return; }
    Mod *m = &mp->m[mi - 1];
    uint64_t low = KEY_LOW(key);
    if (low & (1ull << 40)) { snprintf(out, n, "%s+0x%llx.. (no unwind entry, 256 B)", m->name, (unsigned long long)(low & ~(1ull << 40))); return; }
    const char *ex = export_at(m, (uint32_t)low);
    uint32_t b, e, sz = 0;
    if (func_of(m, (uint32_t)low, &b, &e)) sz = e - b;
    if (ex) snprintf(out, n, "%s!%s (+0x%llx, 0x%x bytes)", m->name, ex, (unsigned long long)low, sz);
    else snprintf(out, n, "%s+0x%llx (0x%x bytes)", m->name, (unsigned long long)low, sz);
}


// ---- late resolution of the looks the sampler could not place ----
// [x28] names the block the dispatcher last entered; code reached through a direct link between blocks runs in another block, so the hostPC test fails. The block that holds the
// pc is found by looking backwards for a block header (a word that points past the pc to a tail that the engine's resolver accepts).
static double now_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
// remembers the 4 KB pages that no block was found for (a direct-mapped table), so a hot page is searched once
static uint64_t no_block_page[8192];
static uint64_t no_native_mb[1024];

static uint64_t late_block_rip(uint64_t pc) {
    static uint64_t c_begin, c_end;
    const char *why = "";
    if (no_block_page[(pc >> 12) & 8191] == (pc >> 12) + 1) return 0;
    if (c_begin && pc >= c_begin && pc < c_end) { uint64_t r = ios_native_rip_from_hostpc(c_begin, pc, &why); if (r) return r; }
    uint64_t lo = pc > (1u << 20) ? pc - (1u << 20) : 0x10000;
    for (uint64_t chunk_end = (pc + 4 + 3) & ~3ull; chunk_end > lo;) {
        uint64_t cs = chunk_end > lo + 0x10000 ? chunk_end - 0x10000 : lo;
        uint32_t buf[0x4000 + 2];
        size_t nwords = (chunk_end - cs) / 4;
        if (!rd(cs, buf, nwords * 4)) { chunk_end = cs; continue; }
        for (size_t i = nwords; i-- > 0;) {
            uint64_t cand = cs + i * 4;
            if (cand > pc) continue;
            uint32_t v = buf[i];
            if (v < 0x20 || v > (1u << 20) || v <= pc - cand) continue;
            uint64_t r = ios_native_rip_from_hostpc(cand, pc, &why);
            if (r) { c_begin = cand; c_end = cand + v + 0x40; return r; }
        }
        chunk_end = cs;
    }
    no_block_page[(pc >> 12) & 8191] = (pc >> 12) + 1;
    return 0;
}

// An ARM64EC module's native code runs from a copy in the JIT pool; the copy begins with the PE header, so the module is found by looking back for it.
static Mod *native_module(uint64_t pc) {
    for (int i = 0; i < nnat; i++) if (pc >= natmods[i].base && pc < natmods[i].base + natmods[i].size) return &natmods[i];
    if (no_native_mb[(pc >> 20) & 1023] == (pc >> 20) + 1) return NULL;
    uint64_t lo = pc > (48ull << 20) ? pc - (48ull << 20) : 0x10000;
    for (uint64_t a = pc & ~0xfffull; a >= lo; a -= 0x1000) {
        uint16_t mz = 0; uint32_t lf = 0;
        if (!rd(a, &mz, 2) || mz != 0x5a4d || !rd(a + 0x3c, &lf, 4) || lf > 0x1000) continue;
        uint32_t sig = 0, size = 0;
        if (!rd(a + lf, &sig, 4) || sig != 0x4550 || !rd(a + lf + 0x18 + 56, &size, 4) || a + size <= pc) continue;
        if (nnat >= MAX_NAT) return NULL;
        Mod *m = &natmods[nnat++];
        memset(m, 0, sizeof *m);
        m->base = a; m->size = size; strcpy(m->name, "?");
        uint32_t dd[2] = {0};
        if (rd(a + lf + 0x88, dd, 8) && dd[0]) {   // the export directory names the DLL
            uint32_t nrva = 0; char nm[40] = {0};
            vm_size_t got = 0;
            if (rd(a + dd[0] + 12, &nrva, 4) && nrva) { vm_read_overwrite(mach_task_self(), (vm_address_t)(a + nrva), 39, (vm_address_t)nm, &got); if (nm[0]) strcpy(m->name, nm); }
        }
        return m;
    }
    no_native_mb[(pc >> 20) & 1023] = (pc >> 20) + 1;
    return NULL;
}

static void late_resolve(void) {
    size_t tried = 0, blk = 0, nat = 0, skipped = 0;
    double t0 = now_s();
    memset(no_block_page, 0, sizeof no_block_page); memset(no_native_mb, 0, sizeof no_native_mb);
    for (size_t s = 0; s < g.n; s++) {
        Sample *sm = &g.samples[s];
        if (sm->kind) continue;
        if ((s & 63) == 0 && now_s() - t0 > 8.0) { skipped = g.n - s; break; }
        Dl_info d;
        if (dladdr((void *)sm->pc, &d) && d.dli_fname) continue;   // a named image: the engine, the system
        tried++;
        uint64_t r = late_block_rip(sm->pc);
        if (r) { sm->rip = r; sm->kind = 1; blk++; continue; }
        if (native_module(sm->pc)) { sm->rip = sm->pc; sm->kind = 2; nat++; }
    }
    size_t yl = 0;
    for (size_t s = 0; s < g.n; s++) {   // a thread in swtch_pri (sched_yield) is waiting for its turn, not computing: kept apart from the shares below
        Sample *sm = &g.samples[s]; Dl_info d;
        if (!sm->kind && dladdr((void *)sm->pc, &d) && d.dli_sname && !strcmp(d.dli_sname, "swtch_pri")) { sm->kind = 3; yl++; }
    }
    say("[prof] looks of threads inside a yield (sched_yield, waiting for their turn, not using the CPU): %zu of %zu (%.0f%%); the shares below leave them out", yl, g.n, 100.0 * yl / (g.n ? g.n : 1));
    say("[prof] looks outside any named image: %zu, of them placed in a translated block: %zu, in the native code of a module copy: %zu, left over: %zu (searched for %.1f s%s)", tried, blk, nat, tried - blk - nat,
        now_s() - t0, skipped ? ", stopped at the time limit" : "");
}

// nearest export at or below rva: the function a native ARM64EC address most likely belongs to
static int nearest_export(Mod *m, uint32_t rva, uint32_t *exrva, const char **name) {
    pe_load(m);
    if (!m->ex || !m->nex) return 0;
    uint32_t lo = 0, hi = m->nex;
    while (lo < hi) { uint32_t mid = (lo + hi) / 2; if (m->ex[mid].rva <= rva) lo = mid + 1; else hi = mid; }
    if (!lo) return 0;
    *exrva = m->ex[lo - 1].rva; *name = m->ex[lo - 1].name;
    return rva - *exrva < 0x4000;
}

// ---- host (native) symbols ----

typedef struct { char key[420]; } Key;
typedef struct { int count; const char *key; } Tally;
static int cmp_key(const void *a, const void *b) { return strcmp(((const Key *)a)->key, ((const Key *)b)->key); }
static int cmp_tally(const void *a, const void *b) { return ((const Tally *)b)->count - ((const Tally *)a)->count; }

static void symbolize(uint64_t pc, char *out, size_t n) {
    Dl_info d;
    if (pc && dladdr((void *)pc, &d) && d.dli_fname) {
        const char *base = strrchr(d.dli_fname, '/'); base = base ? base + 1 : d.dli_fname;
        if (d.dli_sname) snprintf(out, n, "%s`%s", base, d.dli_sname);
        else snprintf(out, n, "%s+0x%llx", base, (unsigned long long)(((uint64_t)pc - (uint64_t)d.dli_fbase) & ~0xfffULL));
    } else snprintf(out, n, "code at 0x%llx (host JIT pool, a translated module's native part or unknown)", (unsigned long long)(pc & ~0xfffffULL));
}
static int is_syscall_image(const char *s) {
    return strstr(s, "libsystem_kernel") || strstr(s, "libsystem_pthread") || strstr(s, "libdispatch") || strstr(s, "libsystem_c");
}

// ---- report ----

typedef struct { uint64_t key, ckey; } Pair;
static int cmp_pair(const void *a, const void *b) {
    const Pair *x = a, *y = b;
    if (x->key != y->key) return x->key < y->key ? -1 : 1;
    return x->ckey < y->ckey ? -1 : x->ckey > y->ckey;
}
static int cmp_u64(const void *a, const void *b) { uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b; return x < y ? -1 : x > y; }

typedef struct { uint64_t key; int count; uint64_t c1, c2; int n1, n2; } Func;
static int cmp_func(const void *a, const void *b) { return ((const Func *)b)->count - ((const Func *)a)->count; }

/// th < 0: every thread.
static void dump_code(ModMap *mp, int th, uint64_t key, int rank);
static void report_set(const char *what, int th, ModMap *mp, unsigned want_funcs, unsigned want_host) {
    size_t cnt = 0, gcnt = 0, ncnt = 0, ycnt = 0;
    for (size_t s = 0; s < g.n; s++) if (th < 0 || g.samples[s].th == (uint32_t)th) {
        if (g.samples[s].kind == 3) { ycnt++; continue; }
        cnt++; if (g.samples[s].kind == 1) gcnt++; else if (g.samples[s].kind == 2) ncnt++;
    }
    if (ycnt) say("[prof]   %s: %zu looks were inside a yield and are left out of the shares", what, ycnt);
    if (!cnt) return;
    say("[prof]   %s: %.0f%% of the looks were translated x86 code, %.0f%% native code of Wine's own DLLs (ARM64EC), %.0f%% the engine and the system", what,
        100.0 * gcnt / cnt, 100.0 * ncnt / cnt, 100.0 * (cnt - gcnt - ncnt) / cnt);
    gcnt += ncnt;

    Pair *pairs = malloc(sizeof(Pair) * (gcnt ? gcnt : 1));
    if (pairs) {
        size_t k = 0; uint32_t sz;
        for (size_t s = 0; s < g.n && k < gcnt; s++) {
            Sample *sm = &g.samples[s];
            if ((th >= 0 && sm->th != (uint32_t)th) || (sm->kind != 1 && sm->kind != 2)) continue;
            pairs[k].key = sm->kind == 2 ? key_for_native(sm->pc) : key_for(mp, sm->rip, &sz);
            pairs[k].ckey = sm->cr[0] && sm->kind == 1 ? key_for(mp, sm->cr[0], &sz) : 0;
            k++;
        }
        // by module
        uint64_t *mods = malloc(sizeof(uint64_t) * (k ? k : 1));
        for (size_t i = 0; i < k; i++) mods[i] = KEY_MOD(pairs[i].key);
        qsort(mods, k, 8, cmp_u64);
        char line[500]; int n = snprintf(line, sizeof line, "[prof]   x86 code by module:");
        struct { uint64_t m; int c; } mt[40]; int nm = 0;
        for (size_t i = 0; i < k;) { size_t j = i; while (j < k && mods[j] == mods[i]) j++; if (nm < 40) { mt[nm].m = mods[i]; mt[nm].c = (int)(j - i); nm++; } i = j; }
        for (int a = 0; a < nm; a++) for (int b = a + 1; b < nm; b++) if (mt[b].c > mt[a].c) { typeof(mt[0]) t = mt[a]; mt[a] = mt[b]; mt[b] = t; }
        for (int a = 0; a < nm && a < 8 && n < (int)sizeof line - 80; a++) {
            const char *nmx = mt[a].m == 0 ? "(outside any module)" : (mt[a].m >= 0x100 && mt[a].m - 0x100 < (unsigned)nnat ? natmods[mt[a].m - 0x100].name : (mp && mt[a].m <= (unsigned)mp->n ? mp->m[mt[a].m - 1].name : "?"));
            n += snprintf(line + n, sizeof line - n, " %s %.0f%%", nmx, 100.0 * mt[a].c / (k ? k : 1));
        }
        say("%s", line);
        free(mods);

        // by function with its main callers
        qsort(pairs, k, sizeof(Pair), cmp_pair);
        Func *fs = malloc(sizeof(Func) * (k ? k : 1)); size_t nf = 0;
        for (size_t i = 0; i < k;) {
            size_t j = i; while (j < k && pairs[j].key == pairs[i].key) j++;
            Func *f = &fs[nf++]; memset(f, 0, sizeof *f); f->key = pairs[i].key; f->count = (int)(j - i);
            for (size_t a = i; a < j;) {
                size_t b = a; while (b < j && pairs[b].ckey == pairs[a].ckey) b++;
                int c = (int)(b - a);
                if (c > f->n1) { f->n2 = f->n1; f->c2 = f->c1; f->n1 = c; f->c1 = pairs[a].ckey; }
                else if (c > f->n2) { f->n2 = c; f->c2 = pairs[a].ckey; }
                a = b;
            }
            i = j;
        }
        qsort(fs, nf, sizeof(Func), cmp_func);
        say("[prof]   hottest x86 functions (share of this thread's looks, with the callers that were on top of the call stack):");
        for (size_t i = 0; i < nf && i < want_funcs; i++) {
            char a[220], b[220], c[220];
            key_name(mp, fs[i].key, a, sizeof a);
            say("[prof]     %5.1f%%  %s", 100.0 * fs[i].count / cnt, a);
            if (fs[i].c1) { key_name(mp, fs[i].c1, b, sizeof b); say("[prof]              called from %s (%d%% of its looks)", b, 100 * fs[i].n1 / fs[i].count); }
            if (fs[i].c2) { key_name(mp, fs[i].c2, c, sizeof c); say("[prof]              called from %s (%d%%)", c, 100 * fs[i].n2 / fs[i].count); }
        }
        if (th < 0) for (size_t i = 0; i < nf && i < 10; i++) if (KEY_MOD(fs[i].key) >= 1 && KEY_MOD(fs[i].key) < 0x100) dump_code(mp, th, fs[i].key, (int)i + 1);
        free(fs); free(pairs);
    }

    // native part
    size_t hn = cnt - gcnt;   // (gcnt already holds the native-copy looks)
    if (hn && want_host) {
        Key *keys = malloc(sizeof(Key) * hn); size_t k = 0;
        for (size_t s = 0; s < g.n && k < hn; s++) {
            Sample *sm = &g.samples[s];
            if ((th >= 0 && sm->th != (uint32_t)th) || sm->kind) continue;
            char a[100], b[100];
            symbolize(sm->pc, a, sizeof a);
            if (is_syscall_image(a)) {
                int n = snprintf(keys[k].key, sizeof keys[k].key, "%s", a);
                uint64_t prev = sm->pc;
                uint64_t chain[4] = { sm->lr, sm->fr[0], sm->fr[1], sm->fr[2] };
                for (int c = 0; c < 4; c++) {
                    if (!chain[c] || chain[c] == prev) continue;
                    prev = chain[c];
                    symbolize(chain[c], b, sizeof b);
                    n += snprintf(keys[k].key + n, sizeof keys[k].key - n, "  <-  %s", b);
                }
                // the x86 function that was running when it called in, if the thread is one of the translator's
                if (sm->cr[0]) {
                    uint32_t sz2; uint64_t ck = key_for(mp, sm->cr[0], &sz2);
                    if (KEY_MOD(ck)) { char c2[160]; key_name(mp, ck, c2, sizeof c2); snprintf(keys[k].key + n, sizeof keys[k].key - n, "   [x86 caller: %s]", c2); }
                }
            }
            else snprintf(keys[k].key, sizeof keys[k].key, "%s", a);
            k++;
        }
        qsort(keys, k, sizeof(Key), cmp_key);
        Tally *t = malloc(sizeof(Tally) * (k ? k : 1)); size_t nt = 0;
        for (size_t i = 0; i < k; i++) {
            if (nt && strcmp(t[nt - 1].key, keys[i].key) == 0) t[nt - 1].count++;
            else { t[nt].key = keys[i].key; t[nt].count = 1; nt++; }
        }
        qsort(t, nt, sizeof(Tally), cmp_tally);
        say("[prof]   native code:");
        for (size_t i = 0; i < nt && i < want_host; i++) say("[prof]     %5.1f%%  %s", 100.0 * t[i].count / cnt, t[i].key);
        free(t); free(keys);
    }
}

/// The machine code of one of the hottest x86 functions, as hex in the log, with the 16-byte pieces the looks landed on, so the instructions that cost the time can be read offline.
static void dump_code(ModMap *mp, int th, uint64_t key, int rank) {
    unsigned mi = KEY_MOD(key); uint64_t low = KEY_LOW(key);
    if (!mp || mi < 1 || mi > (unsigned)mp->n || (low & (1ull << 40))) return;
    Mod *m = &mp->m[mi - 1];
    uint32_t b, e;
    if (!func_of(m, (uint32_t)low, &b, &e) || b != (uint32_t)low) return;
    uint32_t len = e - b; if (len > 1536) len = 1536;
    // where in the function the looks were
    uint64_t offs[4096]; size_t no = 0; uint32_t sz;
    for (size_t s = 0; s < g.n && no < 4096; s++) {
        Sample *sm = &g.samples[s];
        if (sm->kind != 1 || (th >= 0 && sm->th != (uint32_t)th)) continue;
        if (key_for(mp, sm->rip, &sz) == key) offs[no++] = (sm->rip - m->base - b) & ~0xfull;
    }
    qsort(offs, no, 8, cmp_u64);
    struct { uint64_t o; int c; } top[4] = {{0,0},{0,0},{0,0},{0,0}};
    for (size_t i = 0; i < no;) {
        size_t j = i; while (j < no && offs[j] == offs[i]) j++;
        int c = (int)(j - i);
        for (int a = 0; a < 4; a++) if (c > top[a].c) { for (int z = 3; z > a; z--) top[z] = top[z - 1]; top[a].o = offs[i]; top[a].c = c; break; }
        i = j;
    }
    say("[prof-code] #%d %s+0x%x size 0x%x (%zu looks); hottest 16-byte pieces at +0x%llx (%d), +0x%llx (%d), +0x%llx (%d), +0x%llx (%d)", rank, m->name, b, e - b, no,
        (unsigned long long)top[0].o, top[0].c, (unsigned long long)top[1].o, top[1].c, (unsigned long long)top[2].o, top[2].c, (unsigned long long)top[3].o, top[3].c);
    uint8_t buf[1536];
    if (!rd(m->base + b, buf, len)) return;
    for (uint32_t o = 0; o < len; o += 96) {
        char hex[200]; uint32_t n = len - o < 96 ? len - o : 96;
        for (uint32_t k = 0; k < n; k++) snprintf(hex + k * 2, 3, "%02x", buf[o + k]);
        say("[prof-code] %s+0x%x +0x%03x %s", m->name, b, o, hex);
    }
}

/// The translated ARM code around the hottest host addresses of x86 code (all threads), as hex: what the translator made of the instructions that cost the time.
static void dump_host_blocks(ModMap *mp) {
    size_t cnt = 0;
    for (size_t s = 0; s < g.n; s++) if (g.samples[s].kind == 1) cnt++;
    if (!cnt) return;
    uint64_t *pcs = malloc(8 * cnt); size_t k = 0;
    for (size_t s = 0; s < g.n && k < cnt; s++) if (g.samples[s].kind == 1) pcs[k++] = g.samples[s].pc & ~0x3full;   // 64-byte pieces
    qsort(pcs, k, 8, cmp_u64);
    struct { uint64_t pc; int c; } top[12]; int nt = 0;
    for (size_t i = 0; i < k;) {
        size_t j = i; while (j < k && pcs[j] == pcs[i]) j++;
        int c = (int)(j - i);
        int pos = nt;
        while (pos > 0 && top[pos - 1].c < c) pos--;
        if (pos < 12) { for (int z = (nt < 12 ? nt : 11); z > pos; z--) top[z] = top[z - 1]; top[pos].pc = pcs[i]; top[pos].c = c; if (nt < 12) nt++; }
        i = j;
    }
    free(pcs);
    for (int t = 0; t < nt && t < 12; t++) {
        uint64_t start = top[t].pc - 0x80;
        uint8_t buf[0x140];
        // the x86 address this piece belongs to
        uint64_t rip = 0;
        for (size_t s = 0; s < g.n; s++) if (g.samples[s].kind == 1 && (g.samples[s].pc & ~0x3full) == top[t].pc) { rip = g.samples[s].rip; break; }
        uint32_t sz; char nm[160] = "?";
        if (rip) key_name(mp, key_for(mp, rip, &sz), nm, sizeof nm);
        say("[prof-host] #%d %d looks at host 0x%llx..+0x40 (x86: %s, rip 0x%llx); the 0x140 bytes from 0x%llx follow", t + 1, top[t].c, (unsigned long long)top[t].pc, nm, (unsigned long long)rip, (unsigned long long)start);
        if (!rd(start, buf, sizeof buf)) continue;
        for (uint32_t o = 0; o < sizeof buf; o += 96) {
            char hex[200]; uint32_t n = sizeof buf - o < 96 ? sizeof buf - o : 96;
            for (uint32_t q = 0; q < n; q++) snprintf(hex + q * 2, 3, "%02x", buf[o + q]);
            say("[prof-host] 0x%llx %s", (unsigned long long)(start + o), hex);
        }
    }
}

static void report(void) {
    int order[MAX_THREADS];
    for (int i = 0; i < g.nrows; i++) order[i] = i;
    for (int i = 0; i < g.nrows; i++)
        for (int j = i + 1; j < g.nrows; j++)
            if (g.rows[order[j]].run > g.rows[order[i]].run) { int t = order[i]; order[i] = order[j]; order[j] = t; }
    // the module list of the process that has most of the translated code
    nmaps = 0;
    ModMap *best = NULL;
    for (int i = 0; i < g.nrows; i++) { ModMap *m = map_for_teb(g.rows[i].teb); if (m && (!best || m->n > best->n)) best = m; }
    say("[prof] done: %.0f s at %d Hz, %zu looks at running threads, %d modules in the game's process (looks at a translated block that could not be resolved to an x86 address: %u)",
        g.seconds, g.hz, g.n, best ? best->n : 0, g.bb_unresolved);
    late_resolve();
    say("[prof] ==== every thread together ====");
    report_set("all threads", -1, best, 25, 12);
    dump_host_blocks(best);
    int shown = 0;
    for (int oi = 0; oi < g.nrows && shown < 8; oi++) {
        int ti = order[oi]; ThreadRow *r = &g.rows[ti];
        if (r->run < 20) break;
        shown++;
        ModMap *mp = map_for_teb(r->teb); if (!mp) mp = best;
        say("[prof] ==== thread %s (%llx): running %.0f%% of the time (%u of %u looks) ====", r->name[0] ? r->name : "unnamed", (unsigned long long)r->tid,
            100.0 * r->run / (r->ticks ? r->ticks : 1), r->run, r->ticks);
        report_set("this thread", ti, mp, 15, 6);
    }
    free(g.samples); g.samples = NULL;
    for (int i = 0; i < nmaps; i++) for (int j = 0; j < maps[i].n; j++) { free(maps[i].m[j].pd); free(maps[i].m[j].ex); }
}

static double mono_s(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static void *run(void *arg) {
    (void)arg;
    pthread_setname_np("porthole-profiler");
    calibrate();
    mach_port_t self = mach_thread_self();
    struct timespec gap = { 0, (long)(1e9 / g.hz) };
    int ticks = (int)(g.seconds * g.hz);
    for (int tick = 0; tick < ticks; tick++) {
        thread_act_array_t list = NULL; mach_msg_type_number_t count = 0;
        if (task_threads(mach_task_self(), &list, &count) == KERN_SUCCESS) {
            for (mach_msg_type_number_t i = 0; i < count; i++) {
                thread_act_t t = list[i];
                if (t != self) {
                    thread_basic_info_data_t bi; mach_msg_type_number_t bc = THREAD_BASIC_INFO_COUNT;
                    int row = row_for(t);
                    if (row >= 0 && thread_info(t, THREAD_BASIC_INFO, (thread_info_t)&bi, &bc) == KERN_SUCCESS && !(bi.flags & TH_FLAGS_IDLE)) {
                        g.rows[row].ticks++;
                        if (bi.run_state == TH_STATE_RUNNING && g.n < g.cap) {
                            arm_thread_state64_t st; mach_msg_type_number_t sc = ARM_THREAD_STATE64_COUNT;
                            uint64_t bb = 0, cr[16], fr[3] = {0, 0, 0}; int have_cr = 0;
                            if (thread_suspend(t) == KERN_SUCCESS) {
                                kern_return_t kr = thread_get_state(t, ARM_THREAD_STATE64, (thread_state_t)&st, &sc);
                                if (kr == KERN_SUCCESS) {
                                    rd((uint64_t)st.__x[28], &bb, 8);   // FEX's per-thread frame: [x28] is the running block's header
                                    have_cr = rd((uint64_t)st.__x[17], cr, sizeof cr);   // FEX's return-address stack: pairs of (x86 return address, host address)
                                    {   // the host call chain by frame pointers, three frames, each read fault-safe and checked to climb
                                        uint64_t fp = (uint64_t)st.__fp, sp = (uint64_t)st.__sp;
                                        for (int f = 0; f < 3 && fp > sp && !(fp & 7); f++) {
                                            uint64_t pr[2];
                                            if (!rd(fp, pr, 16)) break;
                                            fr[f] = pr[1] & 0x7fffffffffull;
                                            if (pr[0] <= fp) break;
                                            fp = pr[0];
                                        }
                                    }
                                }
                                thread_resume(t);
                                if (kr == KERN_SUCCESS) {
                                    Sample *sm = &g.samples[g.n];
                                    memset(sm, 0, sizeof *sm);
                                    sm->pc = (uint64_t)__darwin_arm_thread_state64_get_pc(st);
                                    sm->lr = (uint64_t)__darwin_arm_thread_state64_get_lr(st);
                                    sm->th = (uint32_t)row;
                                    if (bb > 0x10000) {
                                        const char *why = "";
                                        sm->rip = ios_native_rip_from_hostpc(bb, sm->pc, &why);
                                        if (!sm->rip && strstr(why, "outside") == NULL) g.bb_unresolved++;
                                    }
                                    for (int f = 0; f < 3; f++) sm->fr[f] = fr[f];
                                    if (have_cr) for (int c = 0; c < 4; c++) sm->cr[c] = cr[c * 2] > 0x10000 && cr[c * 2] < 0x800000000000ull ? cr[c * 2] : 0;
                                    if (sm->rip) { sm->kind = 1; g.rows[row].guest++; }
                                    g.n++; g.rows[row].run++;
                                }
                            }
                        }
                    }
                }
                mach_port_deallocate(mach_task_self(), t);
            }
            vm_deallocate(mach_task_self(), (vm_address_t)list, count * sizeof(thread_act_t));
        }
        nanosleep(&gap, NULL);
    }
    mach_port_deallocate(mach_task_self(), self);
    g.phase = 2;
    madeira_passprof_dump(g.seconds);
    report();
    g.phase = 3;
    g.running = 0;
    return NULL;
}

int sample_profiler_running(void) { return g.running; }
int sample_profiler_status(double *elapsed, double *length) {
    if (elapsed) *elapsed = g.phase == 1 ? mono_s() - g.t0 : 0;
    if (length) *length = g.seconds;
    return g.phase;
}

int sample_profiler_start(double seconds, int hz, void (*logger)(const char *line)) {
    if (g.running) return 1;
    if (seconds < 1) seconds = 1;
    if (seconds > 120) seconds = 120;
    if (hz < 20) hz = 20;
    if (hz > 1000) hz = 1000;
    memset(&g, 0, sizeof g);
    g.seconds = seconds; g.hz = hz; g.logger = logger;
    g.cap = (size_t)(seconds * hz) * 12;
    g.samples = malloc(g.cap * sizeof(Sample));
    if (!g.samples) return 2;
    madeira_passprof_start();
    g.running = 1; g.phase = 1; g.t0 = mono_s();
    pthread_t p; pthread_attr_t at; pthread_attr_init(&at);
    if (pthread_create(&p, &at, run, NULL) != 0) { g.running = 0; free(g.samples); g.samples = NULL; return 3; }
    pthread_detach(p);
    return 0;
}

// proc_pid_rusage is in libproc, whose header the iOS SDK does not ship; the engine uses it the same way.
extern int proc_pid_rusage(int pid, int flavor, void *buffer);

int cpu_clock_sample(double *p_ms, double *p_cycles, double *wall_ms, double *all_ms, double *energy_nj) {
    struct rusage_info_v6 ru;
    memset(&ru, 0, sizeof ru);
    if (proc_pid_rusage(getpid(), 6, &ru) != 0) return 1;
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    *p_ms = (double)(ru.ri_user_ptime + ru.ri_system_ptime) * tb.numer / tb.denom / 1e6;
    *p_cycles = (double)ru.ri_pcycles;
    *energy_nj = (double)ru.ri_energy_nj;
    *all_ms = (double)(ru.ri_user_time + ru.ri_system_time) * tb.numer / tb.denom / 1e6;
    *wall_ms = (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
    return 0;
}

// ---- why the fast cores may be held back ----

int clamp_thermal_pressure(void) {
    static int token = -1;
    if (token == -1 && notify_register_check("com.apple.system.thermalpressurelevel", &token) != NOTIFY_STATUS_OK) { token = -2; return -1; }
    if (token < 0) return -1;
    uint64_t state = 0;
    if (notify_get_state(token, &state) != NOTIFY_STATUS_OK) return -1;
    return (int)state;
}

typedef uint32_t io_obj_t;
static void cf_num(CFDictionaryRef d, const char *key, char *out, size_t n, const char *label) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = k ? CFDictionaryGetValue(d, k) : NULL;
    if (k) CFRelease(k);
    size_t l = strlen(out);
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) {
        long long x = 0; CFNumberGetValue(v, kCFNumberLongLongType, &x);
        snprintf(out + l, n - l, " %s=%lld", label, x);
    } else if (v && CFGetTypeID(v) == CFBooleanGetTypeID()) {
        snprintf(out + l, n - l, " %s=%s", label, CFBooleanGetValue(v) ? "yes" : "no");
    }
}

void clamp_diag_text(char *out, unsigned long n) {
    out[0] = 0;
    void *io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!io) { snprintf(out, n, "IOKit not available"); return; }
    CFMutableDictionaryRef (*matching)(const char *) = dlsym(io, "IOServiceMatching");
    io_obj_t (*getservice)(mach_port_t, CFDictionaryRef) = dlsym(io, "IOServiceGetMatchingService");
    int (*props)(io_obj_t, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t) = dlsym(io, "IORegistryEntryCreateCFProperties");
    if (!matching || !getservice || !props) { snprintf(out, n, "IOKit calls missing"); return; }
    io_obj_t svc = getservice(0, matching("AppleSmartBattery"));
    if (!svc) { snprintf(out, n, "no AppleSmartBattery service"); return; }
    CFMutableDictionaryRef d = NULL;
    if (props(svc, &d, NULL, 0) != 0 || !d) { snprintf(out, n, "battery properties refused"); return; }
    cf_num(d, "Temperature", out, n, "batteryTemp(0.01C)");
    cf_num(d, "VirtualTemperature", out, n, "virtualTemp");
    cf_num(d, "Voltage", out, n, "mV");
    cf_num(d, "InstantAmperage", out, n, "mA");
    cf_num(d, "CurrentCapacity", out, n, "charge%");
    cf_num(d, "MaxCapacity", out, n, "maxCapacity");
    cf_num(d, "CycleCount", out, n, "cycles");
    cf_num(d, "ExternalConnected", out, n, "plugged");
    cf_num(d, "IsCharging", out, n, "charging");
    cf_num(d, "AdapterPower", out, n, "adapterW");
    if (!out[0]) snprintf(out, n, "battery service has none of the usual keys");
    CFRelease(d);
}

// ---- scheduling hints for the whole process ----

/// Asks the kernel for the highest latency and throughput tiers for this process (what the system's own foreground games get). kr is returned for the log.
int sched_hint_task_qos(int *kr_latency, int *kr_throughput) {
    int latency = 0xFF0001;      // LATENCY_QOS_TIER_0
    int throughput = 0xFE0001;   // THROUGHPUT_QOS_TIER_0
    *kr_latency = task_policy_set(mach_task_self(), 10 /* TASK_BASE_LATENCY_QOS_POLICY */, (task_policy_t)&latency, 1);
    *kr_throughput = task_policy_set(mach_task_self(), 11 /* TASK_BASE_THROUGHPUT_QOS_POLICY */, (task_policy_t)&throughput, 1);
    return 0;
}
