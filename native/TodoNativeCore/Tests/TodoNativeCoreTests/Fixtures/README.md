These fixtures are derived from the Worker source (worker/src/types.ts, push.ts, changes.ts) and the
.NET `"O"` date format, not captured from a live Worker. To check real payloads, drop a capture of
`GET /changes?since=0` into `local/` (git-ignored); LocalCaptureTests will decode it.
