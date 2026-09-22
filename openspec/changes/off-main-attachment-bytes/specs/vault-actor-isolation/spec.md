## ADDED Requirements

### Requirement: Bulk attachment work runs off the main actor

Types in the app target are main-actor isolated unless they say otherwise, and a `nonisolated`
method on an actor describes **who may call it synchronously**, not **where it runs** — it runs on
the caller's thread. Any operation whose cost is proportional to the size of a user's file is
therefore required to state the executor it wants, rather than inherit the caller's.

Bulk attachment work SHALL NOT execute on the main actor. This covers encrypting a file for upload,
decrypting a file after download, reading a picked file into memory, and writing decrypted bytes to
disk. Small fixed-size operations — a wrapped attachment key, an encrypted file name, a generated key
— SHALL stay on the caller's executor, because a thread hop costs more than the work.

Moving work off the main actor does not make it interruptible, and SHALL NOT be described as doing
so: a single buffer cannot be abandoned mid-computation. The hop is an `await` inside the caller's own
task, so cancellation and priority still reach everything around the call, and the call itself is
allowed to finish.

Buffers that a caller zeroes afterwards — attachment plaintext, per-attachment keys — SHALL be handed
to the hop as arguments rather than captured by it. `Data` is copy-on-write and `zeroize()` mutates, so
a second live reference makes it copy first and erase the copy, leaving the original bytes untouched;
a capture keeps a second reference alive for a lifetime no caller can reason about, while a parameter is
released at a call boundary.

#### Scenario: A file is encrypted while the interface stays runnable

- **WHEN** an attachment's bytes are encrypted or decrypted
- **THEN** the operation SHALL run on a background executor
- **AND** work already queued on the main actor SHALL continue to be serviced while it runs

#### Scenario: A file is read without stopping the draw

- **WHEN** the user confirms an upload and the app loads the selected file into memory
- **THEN** the read SHALL NOT occupy the main actor for its duration

#### Scenario: Decrypted bytes reach the disk without blocking

- **WHEN** the user saves an attachment to disk, or opens one in another application via a temporary
      file
- **THEN** the write SHALL NOT occupy the main actor for its duration
- **AND** the plaintext buffer SHALL still be zeroed by the caller afterwards

#### Scenario: Small crypto stays where it is

- **WHEN** the app wraps an attachment key, encrypts a file name, or generates a per-attachment key
- **THEN** the call SHALL be allowed to run synchronously on the caller's executor

#### Scenario: A buffer the caller erases survives the hop as the caller's alone

- **WHEN** bulk work on a `Data` value is moved off the main actor and the caller zeroes that value
      afterwards
- **THEN** the value SHALL reach the background computation as an argument, not as a capture and not as
      a `let` snapshot held beside the hop
- **AND** either of those would leave a second reference to the bytes, which is the condition under
      which `zeroize()` erases a copy and leaves the original in memory
