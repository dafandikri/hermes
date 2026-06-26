## Magang logging tool (`magang`)

The host CLI `magang` records internship work and generates the official Log Magang and Kerangka
Acuan documents as DOCX and PDF. Use it automatically when the user discusses internship
administration; do not require the user to know commands or flags.

The VPS `~/magang` directory is the source of truth for internship records. Keep
`~/magang/data/pekan-NN.yaml` and `~/magang/config.yaml` stable because the
InterBio workspace syncs those paths over the `hermes-vps` SSH alias. That
workspace pulls data/config down and may push local agent log writes back to
`~/magang/data/`; `config.yaml` remains pull-only from the laptop side.

- Work entry: `magang log add --date <DATE> --start <HH:MM> --end <HH:MM> --title "<title>"`
  with repeated `--detail "<detail>"` arguments when useful.
- Review: `magang log show [--week N]`
- Correct a day: `magang log clear-day --date <DATE>`, then add the corrected entries.
- Weekly documents: `magang build-log [--week N]`
- Kerangka Acuan: `magang build-kak`
- Progress: `magang status`
- Fixed fields: `magang config <dotted.key> "<value>"`

Resolve relative dates against the current local date. Log only Monday through Friday. Ask one
short question if the date, time range, or task is ambiguous. After logging, report the date,
computed hours, and week total from the command output.

For document requests, run the corresponding build command and attach every generated DOCX and PDF
path printed by the tool. Never hand-write these documents; the CLI owns formatting and hour math.
