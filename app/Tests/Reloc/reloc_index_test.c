/* Host test for vendor/Madeira/build/ntdll-unix/ios_reloc_index.h (patch 0020): for many regions of synthetic relocation tables, walking only the window gives exactly the DIR64
 * fixups that walking the whole table gives; unsorted tables are not narrowed; a table replaced at the same address is re-indexed; and the window is far cheaper. */
#include "../../../vendor/Madeira/build/ntdll-unix/ios_reloc_index.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

static int failures;
static volatile unsigned long sink;
static void check( int ok, const char *what ) { printf( "%s %s\n", ok ? "ok   " : "FAIL ", what ); if (!ok) failures++; }

static uint64_t rng = 88172645463325252ull;
static unsigned rnd( void ) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (unsigned)(rng >> 11); }

/* One block per page that has entries, ascending; types mixed (0 padding, 3 HIGHLOW, 10 DIR64); sometimes an entry at the very end of the page (offset 0xffc..0xfff). */
static unsigned build_table( unsigned char *buf, unsigned pages, int sorted )
{
    unsigned pos = 0, p;
    for (p = 0; p < pages; p++)
    {
        unsigned n, i;
        if (rnd() % 3 == 0) continue;                                  /* a page without relocations has no block */
        n = 1 + rnd() % 200; if (n & 1) n++;                           /* keep the block 4-byte aligned */
        *(unsigned *)(buf + pos) = sorted ? p * 0x1000 : (pages - 1 - p) * 0x1000;
        *(unsigned *)(buf + pos + 4) = 8 + 2 * n;
        for (i = 0; i < n; i++)
        {
            unsigned type = (rnd() % 5 == 0) ? 0 : (rnd() % 7 == 0 ? 3 : 10);
            unsigned eoff = (rnd() % 11 == 0) ? 0xff8 + rnd() % 8 : rnd() % 0x1000;
            *(unsigned short *)(buf + pos + 8 + 2 * i) = (unsigned short)((type << 12) | eoff);
        }
        pos += 8 + 2 * n;
    }
    return pos;
}

/* The old walk, with the loop body the engine uses: every DIR64 entry whose 8 bytes overlap [off, off+len), summed into a checksum and a count. */
static void walk( const char *rel, const char *rel_end, size_t off, size_t len, unsigned long *count, uint64_t *sum )
{
    while (rel + 8 <= rel_end)
    {
        unsigned page = *(const unsigned *)rel, bs = *(const unsigned *)(rel + 4), j;
        if (bs < 8 || rel + bs > rel_end) break;
        for (j = 0; j < (bs - 8) / 2; j++)
        {
            unsigned short e = *(const unsigned short *)(rel + 8 + 2 * j);
            size_t rva = page + (e & 0xfff);
            if ((e >> 12) != 10 || rva + 8 <= off || rva >= off + len) continue;
            (*count)++; *sum += rva * 2654435761u;
        }
        rel += bs;
    }
}

int main( void )
{
    const unsigned pages = 16384;                                      /* a 64 MB image */
    unsigned char *tab = malloc( pages * 900 ), *tab2 = malloc( pages * 900 );
    unsigned size = build_table( tab, pages, 1 ), t, mismatches = 0, narrowed = 0;
    const char *ws, *we;
    struct timespec a, b;
    double full_ms, win_ms;

    printf( "table: %u bytes for %u pages\n", size, pages );
    for (t = 0; t < 4000; t++)
    {
        size_t off = ((size_t)rnd() % (pages * 0x1000 + 0x2000)) & ~(size_t)((t % 3 == 0) ? 0xfff : 0), len = (t % 5 == 0) ? 0x1000 : 1 + rnd() % 0x20000;
        unsigned long c1 = 0, c2 = 0; uint64_t s1 = 0, s2 = 0;
        walk( (const char *)tab, (const char *)tab + size, off, len, &c1, &s1 );
        if (ios_reloc_window( (const char *)tab, size, off, len, &ws, &we )) { narrowed++; walk( ws, we, off, len, &c2, &s2 ); }
        else walk( (const char *)tab, (const char *)tab + size, off, len, &c2, &s2 );
        if (c1 != c2 || s1 != s2) mismatches++;
    }
    check( mismatches == 0, "narrowed walks find exactly the fixups the full walk finds (4000 random regions, incl. page-aligned and straddling ones)" );
    check( narrowed == 4000, "a well-formed table is narrowed every time" );

    /* regions at the very start, the very end and beyond the image */
    { unsigned long c1 = 0, c2 = 0; uint64_t s1 = 0, s2 = 0; size_t off = pages * 0x1000 - 0x1000;
      walk( (const char *)tab, (const char *)tab + size, off, 0x1000, &c1, &s1 );
      ios_reloc_window( (const char *)tab, size, off, 0x1000, &ws, &we ); walk( ws, we, off, 0x1000, &c2, &s2 );
      check( c1 == c2 && s1 == s2, "the last page of the image" );
      c1 = c2 = 0; s1 = s2 = 0;
      walk( (const char *)tab, (const char *)tab + size, 0, 0x1000, &c1, &s1 );
      ios_reloc_window( (const char *)tab, size, 0, 0x1000, &ws, &we ); walk( ws, we, 0, 0x1000, &c2, &s2 );
      check( c1 == c2 && s1 == s2, "the first page of the image" );
      ios_reloc_window( (const char *)tab, size, (size_t)pages * 0x1000 + 0x100000, 0x1000, &ws, &we );
      check( ws == we, "a region past the image has an empty window" ); }

    /* the cost: one call per page across the whole image, the way the game does it */
    clock_gettime( CLOCK_MONOTONIC, &a );
    { unsigned long c = 0; uint64_t s = 0; unsigned p; for (p = 0; p < 200; p++) walk( (const char *)tab, (const char *)tab + size, (size_t)p * 0x1000, 0x1000, &c, &s ); sink += c + (unsigned long)s; }
    clock_gettime( CLOCK_MONOTONIC, &b );
    full_ms = (b.tv_sec - a.tv_sec) * 1000.0 + (b.tv_nsec - a.tv_nsec) / 1e6;
    clock_gettime( CLOCK_MONOTONIC, &a );
    { unsigned long c = 0; uint64_t s = 0; unsigned p; for (p = 0; p < pages; p++) { ios_reloc_window( (const char *)tab, size, (size_t)p * 0x1000, 0x1000, &ws, &we ); walk( ws, we, (size_t)p * 0x1000, 0x1000, &c, &s ); } sink += c + (unsigned long)s; }
    clock_gettime( CLOCK_MONOTONIC, &b );
    win_ms = (b.tv_sec - a.tv_sec) * 1000.0 + (b.tv_nsec - a.tv_nsec) / 1e6;
    printf( "full walk: %.1f ms for 200 pages (%.2f ms each, so %.0f ms for the whole image); windows: %.1f ms for all %u pages\n", full_ms, full_ms / 200, full_ms / 200 * pages, win_ms, pages );
    check( win_ms < full_ms / 200 * pages / 20, "walking page by page with windows is at least 20 times cheaper than with full walks" );

    /* an unsorted table is left to the old walk */
    { unsigned s2 = build_table( tab2, 512, 0 );
      check( !ios_reloc_window( (const char *)tab2, s2, 0x4000, 0x1000, &ws, &we ), "an unsorted table is not narrowed" ); }

    /* the memory at the same address is replaced by another table: the cached index must not be used */
    { unsigned s3; unsigned long c1 = 0, c2 = 0; uint64_t s1 = 0, sm = 0;
      s3 = build_table( tab2, pages, 1 );
      ios_reloc_window( (const char *)tab2, s3, 0, 0x1000, &ws, &we );
      memcpy( tab2, tab, size ); s3 = size;                           /* same address, same size field, different content */
      walk( (const char *)tab2, (const char *)tab2 + s3, 0x300000, 0x1000, &c1, &s1 );
      if (ios_reloc_window( (const char *)tab2, s3, 0x300000, 0x1000, &ws, &we )) walk( ws, we, 0x300000, 0x1000, &c2, &sm );
      check( c1 == c2 && s1 == sm, "a table replaced at the same address (and size) is re-indexed" ); }

    printf( failures ? "\n%d check(s) FAILED.\n" : "\nAll relocation index checks passed.\n", failures );
    return failures != 0;
}
