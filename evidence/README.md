# Extension D — prove it survives

Two scenarios run against the **dev** release (`http://localhost:8080`) while a
load generator hits it once every ~100 ms and records the HTTP status of every
request. Re-runnable:

```sh
./scripts/prove-node-drain.sh       # -> evidence/node-drain.log
./scripts/prove-rolling-update.sh   # -> evidence/rolling-update.log
```

The load generator (`scripts/soak.sh`) runs a fixed request count and stops
itself; each transcript ends with a summary plus the full per-request log.

## 1. Node drain — `node-drain.log`

Load target `/work?ms=500`, so every request is genuinely in flight for 500 ms
and some are mid-flight when their pod is evicted.

Timeline (from the run committed here):

| time (UTC) | event |
|---|---|
| 03:41:35 | start; dev is 1-1 across the two workers |
| 03:41:45 | `kubectl drain w3w-exercise-worker2` begins |
| 03:41:57 | node drained — the dev pod on it was evicted; the pod on the other worker kept serving (PDB `minAvailable: 1`) |
| 03:42:17 | replacement pod passed readiness after its ~30 s warm-up; deployment back to 2/2 |

**Result: 140 / 140 requests → HTTP 200. Zero failures.**

```
==== soak summary: http://localhost:8080/work?ms=500 ====
requests: 140
by code:
  200: 140
non-2xx: none
```

What carried it: the `NodePort` Service only routes to Ready pods, so the moment
the evicted pod went `Terminating` new requests went to the surviving pod; the
app's own drain sequence let the in-flight 500 ms requests finish; the PDB
stopped `drain` from taking both pods at once.

## 2. Rolling update — `rolling-update.log`

Trigger: `kubectl rollout restart deployment/greeter-dev` — the same path
(`maxUnavailable: 0` / `maxSurge: 1` + readiness + `terminationGracePeriodSeconds`)
a config change through Terraform would take. Load target `/`.

| time (UTC) | event |
|---|---|
| 03:43:36 | rollout starts |
| 03:43:36–03:44:37 | one new pod at a time: comes up, waits out its 30 s warm-up, passes readiness, then an old pod is retired — never below 2 Ready |
| 03:44:37 | rollout complete |

**Result: 140 / 140 requests → HTTP 200. Zero failures.**

```
==== soak summary: http://localhost:8080/ ====
requests: 140
by code:
  200: 140
non-2xx: none
```

## Note on pod placement

After a drain or a rollout both dev replicas sometimes land on the same worker —
the `topologySpreadConstraints` are soft (`ScheduleAnyway`) and Kubernetes does
not rebalance on its own. This is the documented trade-off in `DECISIONS.md`
(hard anti-affinity would strand prod's third replica and stall rollouts on a
2-node cluster). Availability is preserved throughout; the spread self-corrects
on the next rollout, or you can nudge it by deleting the doubled-up pod.
