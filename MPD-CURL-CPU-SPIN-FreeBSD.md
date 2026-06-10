# musicpd 100% CPU while HTTP streaming on FreeBSD — a libcurl leftover-fd spin

**Platform:** FreeBSD 15.1, `audio/musicpd` 0.24.x, `ftp/curl` 8.20.0 (built with the
threaded resolver), upmpdcli serving Qobuz.
**Symptom:** one CPU core pinned at ~100% by `musicpd` while a track is playing
over HTTP. **Audio is unaffected** — the music plays correctly the whole time.

This is *not* a bug in the DRC chain (virtual_oss / brutefir / OSS). It is a
known **libcurl** bug that leaks an event-loop file descriptor into MPD's curl
input plugin. This document records how it was diagnosed and why it belongs
upstream in curl, not in MPD.

---

## TL;DR

* The 100% CPU is a single MPD thread — the global I/O event loop (`io`) —
  busy-looping in `poll()` ~500,000 times/second, each call returning instantly.
* It is polling **two** control fds: a pipe (MPD's own wake fd, healthy) and an
  **eventfd** that is permanently `POLLIN`-ready and never drained.
* On FreeBSD, **MPD never creates an eventfd** (`USE_EVENTFD` is gated on
  `is_linux` in `src/event/meson.build`). So the stuck eventfd can only have been
  created by **libcurl**, which registered it into MPD's event loop via
  `CURLMOPT_SOCKETFUNCTION`.
* libcurl never issues `CURL_POLL_REMOVE` for that fd after it is done with it.
  MPD keeps polling it; the loop relays each spurious wakeup to
  `curl_multi_socket_action()`, which can't clear it → spin.
* This is the bug class fixed by curl commit `17e6f06` / PR #14296
  ("connect: fix connection shutdown for event based processing", curl 8.10.0).
  We are on 8.20.0, which already contains that fix, yet still spin on an
  **eventfd** — i.e. a residual/regressed variant of the same class.
* **MPD has already triaged this as third-party** (issues #2244 and #2229 are
  closed with the `thirdparty` label). A patch to MPD would not be accepted, and
  is not the right fix. The right venue is libcurl.

---

## Why it is harmless to audio

The runaway thread is the curl input event loop, which only *fetches* the stream
into MPD's input buffer. Decoding (`decoder:flac`) and playback
(`output:*` → `/dev/dsp1` → virtual_oss → brutefir → `/dev/dsp0`) run on
**separate threads** and keep up fine. So the box plays music correctly while one
core is wasted. The practical cost is heat/power on a low-power music server and a
permanently busy core — not stutter.

---

## Diagnostic walkthrough (reproducible)

All of the following were run against the live `musicpd` process. `truss`,
`ktrace`, `procstat -f/-kk` and `lldb` need root; `dtrace` needs
`security.bsd.unprivileged_proc_debug=1`.

### 1. Find the hot thread

```
$ procstat -t <pid>
  ... TDNAME              STATE   WCHAN
      io                  run     -        <-- on-CPU, this is the spinner
      rtio                sleep   select
      player              sleep   uwait
      output:DRC-nati     sleep   select
$ procstat -kk <pid>     # io thread:
  ... musicpd  io  kern_poll_kfds+... kern_poll+... sys_poll+...
```

The `io` thread is the global event loop (curl input lives here). `lldb`
confirms the userland stack is `EventLoop::Run` → poll backend → `__sys_poll`.

### 2. See what it is doing

```
$ truss -p <pid>
poll({ 6/POLLIN|POLLERR|POLLHUP  11/POLLIN|POLLERR|POLLHUP }, 2, -1) = 1
... (tens of thousands of identical lines per second)
```

A `-1` (infinite) timeout that returns `1` *immediately*, forever, means one of
fd 6 / fd 11 is permanently ready and never cleared. The `-1` also proves there
is **no pending timer or DeferEvent** (those would force a 0/finite timeout) —
the loop *intends* to block but a control fd won't let it.

### 3. Identify the two fds

```
$ procstat -f <pid>
  FD  T ...  NAME
   6  p ...  -        <-- pipe
  11  E ...  -        <-- eventfd
  15  s ...  TCP ...:443   <-- the stream socket, NOT in the poll set
```

The stream socket (15) is absent from the poll set: curl has paused the transfer
(`curl_easy_pause`, input buffer full at `CURL_MAX_BUFFERED = 512 KB`,
`src/input/plugins/CurlInputPlugin.cxx`) and removed its socket. So the only
thing left to poll are the two control fds.

### 4. Which fd is stuck? Capture the poll *result* (revents)

```
$ dtrace -q -p <pid> -n '
  syscall::poll:entry  /pid==PID/ { self->f=arg0; self->n=arg1; }
  syscall::poll:return /self->f && self->n<=8/ {
    this->p=(struct pollfd*)copyin(self->f,self->n*sizeof(struct pollfd));
    printf("ret=%d fd%d rev=0x%x | fd%d rev=0x%x\n", arg1,
      this->p[0].fd,this->p[0].revents, this->p[1].fd,this->p[1].revents);
    self->f=0; }
  tick-1s { exit(0); }'

ret=1 fd6 rev=0x0 | fd11 rev=0x1     <-- fd11 (eventfd) permanently POLLIN
ret=1 fd6 rev=0x0 | fd11 rev=0x1
...
```

So **fd11, the eventfd, is the spinner**; the pipe (fd6) is quiet.

### 5. Prove it is curl's, not MPD's

Two independent facts:

* **Source:** `src/event/meson.build`:
  `event_features.set('USE_EVENTFD', is_linux and get_option('eventfd'))`.
  On FreeBSD `is_linux` is false → `USE_EVENTFD` undefined → MPD's `WakeFD` is an
  `EventPipe` (a *pipe*), and MPD's only other eventfd user (io_uring) is also
  Linux-only. **MPD creates no eventfds on FreeBSD.** The healthy quiet pipe
  (fd6) *is* MPD's wake fd; the eventfd must be foreign.
* **Behavior:** during the spin there are **zero `read()` syscalls** (dtrace
  `syscall::read:entry` count = 0 while `poll` count ≈ 500k/s). MPD's own wake
  fd, when it fires, is drained with `wake_fd.Read()` (`EventLoop::OnSocketReady`
  in `src/event/Loop.cxx`). fd11 fires every iteration yet is never read — so its
  handler is not MPD's wake handler. It is a `CurlSocket` whose
  `OnSocketReady` calls `curl_multi_socket_action()` (no syscall), which does
  nothing because the bound easy handle is paused.

The only component doing socket I/O on this loop is libcurl. Therefore the stuck
eventfd is a libcurl fd that curl handed to MPD via `CURLMOPT_SOCKETFUNCTION`
(`CurlSocket::SocketFunction` in `src/lib/curl/Global.cxx`) and never asked MPD
to remove.

---

## Root cause

libcurl's multi/socket interface registers a file descriptor for event
monitoring and then fails to send `CURL_POLL_REMOVE` once it is finished with it.
The application (MPD) faithfully keeps polling the fd; because the fd stays
readable (`POLLIN` on the eventfd), every `poll()` returns instantly and the
event loop never sleeps.

This matches curl issue **#14280** ("socket_function callbacks for unrelated
sockets that are never removed") almost exactly. The maintainer (Stefan Eissing)
traced it to the 8.9 connection-shutdown rework:

> *connections being shutdown would register sockets for events, but then never
> remove these sockets again* — curl commit `17e6f06`, "connect: fix connection
> shutdown for event based processing" (PR #14296, in curl 8.10.0).

Another reporter on that issue reproduced the identical behavior on **epoll /
sd-event**, so this is a libcurl-side bug, independent of OS and event backend —
FreeBSD's `poll()` backend is just where we happened to observe it.

### Why it still happens here on curl 8.20.0

Our curl already contains the 8.10 fix, yet still leaks — and the leaked fd is an
**eventfd** (curl's internal connection-shutdown / threaded-resolver wakeup),
whereas #14280's leftovers were ordinary connection sockets. This looks like a
**residual or regressed variant** of the same shutdown-fd-leak class that the
2024 fix did not cover for the eventfd path. That makes a fresh, well-evidenced
**libcurl** report worthwhile — with a minimal standalone `curl_multi`
reproducer (MPD is not accepted as a reproducer upstream).

---

## Where this belongs

| Project | Status |
|---|---|
| **MPD** | Already declined. Issues [#2244] and [#2229] — same symptom ("100% CPU after ~1 min of HTTP streaming") — are **closed with the `thirdparty` label**. MPD correctly honors curl's `SOCKETFUNCTION` contract; the fault is curl's. A patch to MPD will not land. |
| **libcurl** | The correct venue. The bug class is [#14280], fixed for the original case by [PR #14296] (curl 8.10.0). We observe a residual eventfd variant on 8.20.0 — worth reporting with a minimal reproducer. |

[#2244]: https://github.com/MusicPlayerDaemon/MPD/issues/2244
[#2229]: https://github.com/MusicPlayerDaemon/MPD/issues/2229
[#14280]: https://github.com/curl/curl/issues/14280
[PR #14296]: https://github.com/curl/curl/pull/14296

---

## Mitigations / next steps

* **Worth testing locally:** rebuild `ftp/curl` with the **c-ares** resolver
  instead of `THREADED_RESOLVER` (`make config` →
  `OPTIONS_SINGLE_RESOLV = CARES`). If the leaked eventfd is on the threaded
  resolver's shutdown path, this avoids it. Untested.
* **To pursue upstream:** build a minimal `curl_multi` + `socket_action` program
  that streams a large/paused transfer and watch for an fd registered via
  `CURLMOPT_SOCKETFUNCTION` that never receives `CURL_POLL_REMOVE`; capture the
  `eventfd()` creation and the add-without-remove with `ktrace`/`dtrace`. File
  against curl, referencing #14280 / #14296.
* **Do not** patch MPD — it has already been triaged as third-party.

---

## Appendix: handy one-liners

```sh
# Which thread is hot, and its kernel stack
procstat -t <pid>; sudo procstat -kk <pid>

# What the hot thread calls (expect a tight poll() loop)
sudo timeout 2 truss -p <pid> 2>&1 | grep -oE '^[a-z_]+\(' | sort | uniq -c | sort -rn

# Identify the polled fds (pipe vs eventfd vs socket)
sudo procstat -f <pid> | awk 'NR==1 || $3==6 || $3==11 || $3==15'

# Capture poll() revents to see which fd is stuck ready
sudo dtrace -q -p <pid> -n '
  syscall::poll:entry  /pid==PID/ { self->f=arg0; self->n=arg1; }
  syscall::poll:return /self->f && self->n<=8/ {
    this->p=(struct pollfd*)copyin(self->f,self->n*sizeof(struct pollfd));
    printf("fd%d rev=0x%x | fd%d rev=0x%x\n",
      this->p[0].fd,this->p[0].revents,this->p[1].fd,this->p[1].revents);
    self->f=0; } tick-1s { exit(0); }'

# Confirm the stuck fd is never read() (poll spins, read count stays 0)
sudo dtrace -q -p <pid> -n '
  syscall::read:entry /pid==PID/ { @r[arg0]=count(); }
  syscall::poll:return /pid==PID/ { @p=count(); }
  tick-1s { printa(@p); printa("fd%-3d %@d\n",@r); exit(0); }'
```

*Investigated 2026-06-10.*
