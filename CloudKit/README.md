# CloudKit schema

`schema.ckdb` is the source of truth for Fathom's CloudKit container
(`iCloud.com.Vardaan.Fathom`, team `D8B7HB9L2J`). It is applied deliberately
with `cktool`, never auto-created by running the app.

## Why by hand

CloudKit's **production schema is additive-only.** A record type deployed to
production can never be removed; a field can never be retyped or deleted. If
the schema is created implicitly by whatever a Debug build happened to save,
then the shape of the Swift structs on one particular afternoon becomes
permanent — and the development and production environments drift apart with
nothing to compare against.

Keeping the schema in the repo means it gets reviewed like any other code, and
`SchemaFileTests` fails the build if it stops matching what the engine actually
writes.

Field-by-field merge behaviour is specified in
[docs/sync-conflict-policy.md](../docs/sync-conflict-policy.md).

## One-time setup

`cktool` needs a **management token**, which is an account credential — create
it yourself, and do not paste it into a shell command where it will land in
your history.

1. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard/) →
   **Settings** → **Tokens** → **Management Tokens** → create one.
2. Save it via the interactive prompt (no argument, so it is not echoed or
   stored in shell history):

```bash
xcrun cktool save-token --type management
```

## Applying the schema

Validate first. This is read-only and is the safety net for a hand-written
file:

```bash
xcrun cktool validate-schema --team-id D8B7HB9L2J --container-id iCloud.com.Vardaan.Fathom --environment development --file CloudKit/schema.ckdb
```

Then import to **development**:

```bash
xcrun cktool import-schema --team-id D8B7HB9L2J --container-id iCloud.com.Vardaan.Fathom --environment development --validate --file CloudKit/schema.ckdb
```

Confirm what actually landed, rather than trusting the import's exit code:

```bash
xcrun cktool export-schema --team-id D8B7HB9L2J --container-id iCloud.com.Vardaan.Fathom --environment development
```

The export is CloudKit's own rendering, so it will not be byte-identical to
this file — comments are dropped and ordering may differ. Compare record types
and field names and types.

## Promoting to production

**This is the irreversible step.** Do it only after the development environment
has been exercised by a real two-device run: a book imported on one device and
opened on the other, a highlight made and deleted, a book removed from a shelf,
and reading time logged on both devices on the same day.

```bash
xcrun cktool import-schema --team-id D8B7HB9L2J --container-id iCloud.com.Vardaan.Fathom --environment production --validate --file CloudKit/schema.ckdb
```

TestFlight and App Store builds always use the **production** environment, so
this has to happen before any build goes to a tester. Otherwise the tester's
device is the first thing that ever creates production schema, and it creates
it from whatever it happens to save.

## Changing the schema later

1. Change the code.
2. Change `schema.ckdb` to match — `SchemaFileTests` will fail until you do.
3. `validate-schema`, then `import-schema` to development.
4. Only add. Removing a field or a record type is not possible in production;
   retiring one means leaving it in place and ignoring it in code.

`cktool reset-schema` resets **development** to match production and deletes
all development data. It does not undo a production deploy — nothing does.
