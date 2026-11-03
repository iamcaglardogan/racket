# RACKET interface

The owner delegated the complete product flow and implementation on October 15, 2026, including progress through the previous phase checkpoints. This document records the design chosen under that authorization.

RACKET uses a quiet native macOS sidebar and a warm paper surface, dark ink, and a restrained burgundy accent. Storage figures use tabular digits. System colors provide a corresponding dark appearance. The interface favors real paths, file counts, allocated sizes, and ordinary actions over health scores or promised speed improvements.

## Workflow

- Overview: volume capacity, filesystem free space, last scan, and clear entry points.
- Cleanup: explicitly enabled, verified categories; scan progress and cancellation; searchable results with no default selection; exact file review before Trash.
- Creative: available creative rules and their verification state. Unverified categories explain why they cannot run.
- Storage: a folder chosen by the user; bounded read-only allocated-size exploration with visible incomplete coverage and Finder actions.
- Applications: installed app metadata, an explicit app review and narrow safe removal, with refused applications explained.
- Recovery: authenticated session history, individual operation results, and undo without overwriting existing items.
- Settings: appearance, launch at login, menu bar, opt-in scheduled scans and exclusions. Scheduled work only scans and reports; it never removes files.

## Review and accessibility

Every cleanup finding shows its path, allocated size, modification date, rule explanation, regeneration cost, and source. Selection is explicit and persists only for a particular completed scan. Changes invalidate selection. Confirmation names the exact selection and explains that Trash occupies storage until emptied. A failed or partial scan remains visible.

Native buttons, toggles, menus, tables, and sheets retain keyboard behavior and VoiceOver labels. Scan uses Command-R; search uses Command-F; destructive confirmation has a cancel action and no Return shortcut. Motion is minimal and honors Reduce Motion. Color never provides the sole indication of status. Minimum supported layout is 980 × 680 with resizable split navigation.

## Tokens

| Token | Light | Dark |
| --- | --- | --- |
| Canvas | #F5F3EE | Native window background |
| Surface | Native control background | Native control background |
| Ink | Native primary label | Native primary label |
| Secondary | Native secondary label | Native secondary label |
| Accent | #713344 | #CE899A |
| Radius | 16 points | 16 points |
| Spacing | 8, 12, 16, 24, 32 points | Same |

This is the local product direction, not a Figma artifact or an assertion of completed accessibility verification.
