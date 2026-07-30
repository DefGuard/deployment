# OVA structural migrations

`dg-ctl upgrade` runs these when it needs to change the layout of
`/opt/stacks/defguard` or `/opt/defguard` in a way the compose template
regeneration alone can't express (moving/renaming a volume directory, seeding
a new required `.env` var, dropping a new file under `init/`, etc).

## Adding one

1. Add a script here named after the OVA version that introduces the change,
   e.g. `2.2.0.sh`.
2. List that version in `migrations` in `ova/manifest.json`, in ascending
   order.
3. The script receives, as environment variables:
   - `STACK_DIR` - the stack directory (`/opt/stacks/defguard`)
   - `OVA_DIR` - the OVA CLI directory (`/opt/defguard`)
   - `ENV_FILE` - `$STACK_DIR/.env`
   - `FROM_VERSION` / `TO_VERSION` - the OVA versions being upgraded between
4. Exit non-zero to abort the upgrade. The pre-upgrade backup has already been
   taken by this point, and the compose file/tags have not yet been touched,
   so `dg-ctl rollback <id>` is always safe to run after a failed migration.
5. Scripts must be idempotent: `dg-ctl upgrade` can be re-run after a partial
   failure, and `resolve_pending_migrations` decides what's pending from the
   *target* OVA version, not from what actually ran last time.

`dg-ctl` only runs migrations with `FROM_VERSION < version <= TO_VERSION`
(string `FROM_VERSION`/`TO_VERSION` of `unknown` or `*-unknown`, from OVAs
that predate `state.json`, are treated as version `0.0.0` - every migration
runs).
