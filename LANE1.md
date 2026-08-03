# Lane 1 — capture + transport. Start here.

Nikhil's lane. Everything below is built and in the repo; this page is the
order to do things in and the three decisions that need the team's eyes.

---

## 1. Local Docker or cloud free tier? — **Local, and here is the reasoning**

Use `laser-stack` via Docker as the primary. Four reasons, in order of weight:

1. **Venue wifi is a single point of failure for a live-streaming demo.** The
   whole pitch is "every event visibly streams." At a 350-person hackathon on
   shared wifi, a cloud round-trip per event is the one dependency that can
   kill the demo in front of judges. Local is loopback.
2. **The doc already picked this shape.** "Everything on the demo Mac or in
   throwaway free-tier accounts, synthetic data only." At showtime the capture
   app and FalkorDB are both on the demo Mac anyway — the stream should be too.
3. **It is not a downgrade.** Laser Stack runs the same Apache Iggy build plus
   the same `laser-plane`, so `capabilities()` reports `managed: true` and the
   query/watch features work exactly as they do in cloud. Images are published
   for arm64, so Apple Silicon pulls natively.
4. **Zero signup friction.** `./scripts/up` prints the connection string.

**The catch, and it is real:** local Laser Stack binds `127.0.0.1` only. It is a
single-machine stack. That is fine because of how the lanes are already split —
the graph lane develops against fixtures by design and can run its own local
stack, and at demo time everything converges on one Mac. But it means:

> Do **not** plan on a shared dev stream between machines from the local stack.
> If the team wants one, that is the one thing worth a cloud free-tier account.

**Recommendation: both, costing nothing.** Everyone runs local. Whoever wants a
shared stream also makes a free cloud account. The connection string is a single
env var — `LASER_CONNECTION_STRING` — and no code anywhere in this repo hardcodes
a target. Switching is one export.

### ⚠️ Port collision — fix this before you start

`laser-stack` puts Iggy's HTTP listener on **3000**. The FalkorDB command in our
base README puts FalkorDB's browser UI on **3000** as well. On the demo Mac both
run at once and the second one to start fails.

In `laser-stack/.env`:

```bash
LASER_IGGY_HTTP_PORT=3100     # Iggy HTTP moves; FalkorDB keeps 3000
```

Tell the graph lane. This is a ten-second fix now and a confusing ten-minute
failure at 13:00.

---

## 2. Setup, in order

```bash
# a. Laser Stack up (its own clone, outside our repo)
git clone https://github.com/laserdata/laser-stack.git
cd laser-stack
./scripts/up                       # creates .env, waits for health, PRINTS the connection string
# edit .env first if you want LASER_IGGY_HTTP_PORT=3100 — see the collision note above

# b. Point our repo at it
cd ../onari-ambient-capture
echo "LASER_CONNECTION_STRING='iggy:laser@127.0.0.1:8090'" >> .env
export LASER_CONNECTION_STRING='iggy:laser@127.0.0.1:8090'

# c. The LaserData smoke test (the 4th one the base README asks for)
pip install laser-sdk
python3 laser-bridge/smoke_laser.py        # -> LASERDATA_SMOKE_GREEN

# d. Build the Mac app. Run this from capture-mac/, not from the repo root.
cd capture-mac
swift build
swift test
```

**If you only have ten minutes**, skip a–c entirely and run
`python3 laser-bridge/bridge.py --stdout`. It validates and prints every event
with no LaserData, no Docker, no SDK. The Mac app can be fully verified against
it, and you swap in the real transport later by dropping the flag.

---

## 3. What is built

### `capture-mac/` — blocks A, B, C

| File | Does |
|---|---|
| `Contract/AmbientEvent.swift` | The four event types, encoding pinned to `event-contract.json` |
| `Contract/BoardIdentity.swift` | `board_id` as a **derived** UUIDv5 over (app, normalized title) |
| `Capture/ActiveWindowProbe.swift` | NSWorkspace + Accessibility API → app, window title, focused field |
| `Capture/SwitchChain.swift` | Samples → switch events: dedupe, settle, `seq`, `dwell_ms_from` |
| `Capture/EventPublisher.swift` | Batched POST to the bridge + durable JSONL spool |
| `Capture/HotKey.swift` | Global ⌥⌘Space, press-and-hold |
| `Notiz/MicNoteRecorder.swift` | Mic → WAV → transcript, bound to (app, window, time) |
| `Capture/CaptureCoordinator.swift` | Wires it together |
| `App.swift` | Menu-bar state dot: ◉ green · ◎ degraded · ● recording |

Three decisions inside worth knowing about:

**`board_id` is derived, not random.** UUIDv5 over `app|normalized-title`. The
same window seen twice in a session is the same board — otherwise the wander
chain shows ten boards instead of four and the consolidation view is nonsense.
Normalization strips unread counts (`(3) LinkedIn`) and editor dirty markers
(`• file.swift`) so a notification does not fork a board. `laser_common.py`
computes the identical value in Python, with cross-language vectors pinned in
the tests — the graph lane can derive a board_id without asking the Mac.

**Transcription is Apple on-device by default, with a Parakeet seam.** The doc
mandates Parakeet; Parakeet on Apple Silicon means `parakeet-mlx`, a Python
dependency plus a model download. `SFSpeechRecognizer` is on-device, ships with
macOS, needs no download, and is good enough for six scripted phrases. Parakeet
drops in with **no Swift changes**:

```bash
export ONARI_TRANSCRIBE_CMD="uv run parakeet-mlx-transcribe"   # gets the WAV path appended
```

**The publisher cannot lose an event.** Every event is appended to
`~/Library/Application Support/Onari/ambient-events.jsonl` *before* the POST is
attempted. Bridge down, wifi dead, Docker restarted — the spool is the record:
`python3 laser-bridge/bridge.py --replay <that file>`.

### `laser-bridge/` — the transport

Full detail in `laser-bridge/README.md`. The short version: Swift POSTs NDJSON
to loopback, Python publishes with the real SDK, and every event is validated
against the contract before it goes out. Verified end to end — all 8 repo
fixtures replay clean, malformed events are rejected with a reason.

---

## 4. Permissions — do this in the first hour, not at 14:00

Two TCC dialogs. Both are the classic hackathon time-sink when they surface
mid-demo.

- **Accessibility** — needed for window *titles*. Without it the app still runs
  and still emits app-level switches; titles fall back to the app name. Menu →
  "Open Accessibility settings…".
- **Microphone + Speech Recognition** — prompted at launch.

`swift run` from a bare SPM binary has no Info.plist, and TCC kills a process
that touches the mic without one. `Package.swift` section-creates `Info.plist`
into the binary to handle this, which is why **you must run `swift build` from
inside `capture-mac/`** — the linker resolves that path relative to the working
directory. If the linker complains, delete the `linkerSettings` block and build
a real `.app` bundle instead; that is the more reliable TCC path anyway.

---

## 5. Three things for the team, not for me

1. **The Guild reachability question.** Guild.ai is managed/cloud. FalkorDB and
   LaserData are both local Docker on the demo Mac. A cloud-hosted agent cannot
   reach `127.0.0.1`. So: does Guild *pull* from FalkorDB, or does a local
   process assemble the intent frame and *push* it to Guild? If it pulls, the
   graph and the stream have to be cloud-hosted or tunnelled, and that changes
   lane 2's setup — not lane 1's. **Raise this at the 13:00 regroup at the
   latest**; it is the only cross-lane assumption I could not verify from the
   doc, and it lands on lane 3 hardest.

2. **The stream/topic mapping.** The contract says "streams"; Laser's model is
   stream → topic. I mapped both contract streams onto topics inside one Laser
   stream named `onari`. If the graph lane assumed two separate Laser *streams*,
   we disagree by one line of config — thirty seconds to fix now, a confusing
   empty-topic at 13:00 otherwise.

3. **The port collision above.** `LASER_IGGY_HTTP_PORT=3100`.

---

## 6. What is not done

- **Block E / `ChatLogReader`** — `delta` events (an assistant answer arriving
  while you are elsewhere). The type is implemented and the fixture exists, so
  the demo beat works from fixtures. This is the right thing to cut if time runs
  short; it costs the demo nothing.
- **Pass-through dictation** — `NoteEvent.mode = .passthrough` and the field
  probe (`focusedFieldDescription`) are both written, but nothing types the text
  into the focused field yet. Roughly 30 minutes with `CGEvent` keyboard
  synthesis.
- **Block D / `BoardListView`** — deliberately skipped. The doc says the
  consolidated view is lane 2/3's surface, and the capture app is supposed to
  have no standing UI beyond the state dot.
