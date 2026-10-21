# Maintenance

* [Compaction and File Sizing](compaction-and-file-sizing.md) - Why small files hurt performance and how to compact them with rewrite_data_files (bin-pack, sort, z-order).
* [Expire Snapshots](expire-snapshots.md) - Why snapshots need expiring, retention settings, and interaction with time travel and branches/tags.
* [Remove Orphan Files](remove-orphan-files.md) - What orphan files are, how remove_orphan_files finds and deletes them, and safety considerations.
* [Rewrite Manifests](rewrite-manifests.md) - Why manifests fragment and how rewriting them speeds up scan planning.
* [Post-Update Maintenance Runbook](post-update-maintenance-runbook.md) - Ordered, copy-paste steps after a massive MERGE/UPDATE/DELETE: diagnose, delete-aware compaction, delete-file compaction, manifests, snapshot expiry and orphan cleanup at scale, stats.
* [Maintenance Scheduling and Strategy](maintenance-scheduling-and-strategy.md) - Synthesis: recommended cadence and ordering for maintenance operations in production.
