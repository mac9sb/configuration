# Single-Node Mac Server with Tiered Storage & Hierarchical Backups

This document describes a **deliberately honest, single-machine architecture**: a Mac acting as a small server with direct-attached storage (DAS), clear data ownership, and layered backups designed to fail predictably.

This is **not** a NAS, **not** a cluster, and **not** pretending to be highly available.
It is fast, understandable, and survivable.

---

## 1. System Goal

Build a reliable small server that:

- prioritises local performance
- uses explicit storage tiers
- protects against human error, disk failure, and physical loss
- remains simple enough to reason about under stress

If the Mac disappears, recovery is possible.
If a drive disappears, recovery is boring.
If you make a mistake, recovery is fast.

---

## 2. Storage Topology (Authoritative)

### 2.1 Internal Mac SSD — **Hot Tier**

**Purpose**
- Running applications and services (Swift binaries, web servers)
- In-memory or ephemeral stores (Redis-like, caches)
- Build artefacts, logs, temp data

**Rules**
- No long-term state lives here
- Losing this disk must not lose irreplaceable data
- Consider everything here disposable

---

### 2.2 External 4-Bay DAS Enclosure — **Persistent Storage**

All drives:
- APFS
- Encrypted
- Fixed mount points
- Explicit ownership and permissions

---

#### Drive 1 — Time Machine (Machine Recovery)

**Purpose**
- macOS rollback
- App reinstalls
- Configuration recovery
- “I broke the system” events

**Rules**
- Time Machine only
- No application data depends on this drive
- Protects the *Mac*, not the services

---

#### Drives 2 & 3 — Application Long-Term Storage (Warm Tier)

**Purpose**
- SQLite databases
- Assets
- Uploaded files
- Any data that must persist across restarts

**Rules**
- Applications read/write here
- SQLite must live on direct-attached storage only
- No backups stored here
- No Time Machine reliance

This is the **truth layer** for running services.

---

#### Drive 4 — Immutable Backups (Cold Tier)

**Purpose**
- Point-in-time backups of databases and assets
- Long-term recovery
- Audit-friendly storage

**Rules**
- Append-only
- No deletes
- No overwrites
- Applications never read from it
- Prefer write-only service user
- Human interaction discouraged

Backups here are **records**, not tools.

---

## 3. Backup Philosophy

- Time Machine = **convenience**
- tar.gz archives = **truth**
- Higher layers derive from lower layers
- Nothing ever mutates older backups
- Clarity beats cleverness

---

## 4. Backup Cadence & Aggregation (Pyramid Model)

### Core Principle

> Lower levels are for precision.
> Higher levels are for survivability.

---

## 5. Daily Backups (Per Project)

**When**
- Daily (low-load window)

**What**
- Each project backed independently
- SQLite dumps
- Asset snapshots
- Manifest metadata

**Output**
```
/backups/projects/<project>/daily/
YYYY-MM-DD.tar.gz
```

**Rules**
- Append-only
- Never overwritten
- No cross-project mixing

Use this for **surgical restores**.

---

## 6. Weekly Roll-ups (Sundays)

**When**
- Sunday night / early Monday

**What**
- Tar all daily archives for the week

**Output**
```
/backups/projects/<project>/weekly/
YYYY-W##.tar.gz
```

**Rules**
- ISO week numbering
- Immutable once created
- Daily archives may be pruned *after verification*

---

## 7. Monthly Roll-ups (1st of Month)

**When**
- 1st day of each month

**What**
- Tar all weekly archives from the previous month

**Output**
```
/backups/projects/<project>/monthly/
YYYY-MM.tar.gz
```

**Rules**
- Only completed weeks included
- Weekly archives remain untouched

---

## 8. Quarterly Roll-ups (Months 3, 6, 9, 12)

**When**
- End of March, June, September, December

**What**
- Tar all monthly archives in the quarter

**Output**
```
/backups/projects/<project>/quarterly/
YYYY-Q#.tar.gz
```

**Rules**
- Strict calendar quarters
- No recompression tricks
- Clarity over optimisation

---

## 9. Yearly Roll-ups (End of Year)

**When**
- End of year, after Q4 completes

**What**
- Tar all quarterly archives

**Output**
```
/backups/projects/<project>/yearly/
YYYY.tar.gz
```

**Rules**
- One archive per year
- Treated as effectively permanent
- Ideal for deep cold storage

---

## 10. Retention Policy (Baseline)

Suggested defaults:

- Daily: 14–30 days
- Weekly: 2–3 months
- Monthly: 1–2 years
- Quarterly: long-term / indefinite
- Yearly: permanent

**Pruning Rules**
- Never prune upwards automatically
- Always verify derived archives before pruning lower layers
- Logs outlive the backups they describe

Deletion must feel deliberate.

---

## 11. Integrity & Audit Metadata

Each archive should include:

- `manifest.json`
  - file list
  - sizes
  - checksums
- backup timestamp
- source identifier

Optional but recommended:
- checksum of the tar.gz itself
- verification before off-site upload

Backups without metadata are **hope**, not strategy.

---

## 12. Off-Site / Cloud Backups

**What goes off-site**
- Weekly and above by default
- Daily stays local unless needed

**Flow**
```
SQLite / assets
→ tar.gz (Drive 4)
→ encrypt
→ upload to object storage
```

**Rules**
- Restore-only mindset
- No live application writes
- No filesystem semantics assumed

---

## 13. Security Posture

### Logical
- Full-disk encryption everywhere
- Separate service users
- Minimal permissions
- Write-only backups
- Read-only mounts where possible

### Physical
- Lock the door
- Lock the Mac
- Auto-lock on sleep
- No exposed drives

Most losses are physical or accidental.
This plan targets reality.

---

## 14. Operational Rules

- Backups are scheduled, boring, and pull-based
- Restore tests happen occasionally
- Mount points are fixed and documented
- No “temporary” exceptions
- Anything confusing gets written down

Complexity grows silently. Documentation stops it.

---

## 15. Failure Modes (Expected & Acceptable)

| Event | Outcome |
|-----|--------|
| App crash | Restart, data intact |
| Single drive failure | Restore from backups |
| Mac failure | Replace Mac, restore data |
| Site loss | Restore from off-site archives |
| Human mistake | Time Machine or snapshot rollback |

No mysteries. No heroics.

---

## 16. Final Statement

This system is:

- fast where it needs to be
- boring where it matters
- honest about what it is

It avoids pretending to be a NAS or a cluster, while still delivering **predictable recovery and long-term safety**.

If it ever outgrows this design, you will know **exactly which layer to replace**.

That’s the point.
