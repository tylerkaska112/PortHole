// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Porthole authors. See LICENSE.
#ifndef SAMPLE_PROFILER_H
#define SAMPLE_PROFILER_H

/// A sampling profiler for the whole process (the game's threads, the engine's and the in-process wineserver): for a few seconds it looks, `hz` times a second, at
/// every thread that is running and notes where it is. The result goes to `logger` as lines, most-used places first, per thread.
/// Log-only; it slows the game a little while it runs. Returns 0 when it started.
int sample_profiler_start(double seconds, int hz, void (*logger)(const char *line));
int sample_profiler_running(void);
/// 0 never started, 1 looking at the threads (*elapsed seconds so far, of the length asked), 2 working out the result, 3 finished (the result is in the log).
int sample_profiler_status(double *elapsed, double *length);

/// The process's performance-core time and cycles so far, for the clock the fast cores run at (cycles / time): `p_ms` is the time the process spent on fast cores,
/// `p_cycles` the cycles it ran there, `wall_ms` the monotonic clock. Returns 0 when the system gave the numbers.
int cpu_clock_sample(double *p_ms, double *p_cycles, double *wall_ms, double *all_ms, double *energy_nj);
/// Highest kernel latency/throughput tiers for the process; the two return codes are written for the log.
int sched_hint_task_qos(int *kr_latency, int *kr_throughput);

/// What iOS says about why it may be holding the processor back, as one line of text (battery details through IOKit when the system lets an app read them).
void clamp_diag_text(char *out, unsigned long n);
/// The system's thermal pressure level (the finer number behind ProcessInfo.thermalState), -1 when it cannot be read.
int clamp_thermal_pressure(void);

#endif
