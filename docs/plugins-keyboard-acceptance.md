# Plugin acceptance: keyboard first

Status: acceptance checklist, not a test report. Unchecked items require verification in a running shell.

## Common
- [ ] Open panel, choose each plugin, enter content, return to tabs, close and reopen without mouse.
- [ ] Selected item has a visible focus indicator and scrolls into view.
- [ ] Arrow keys and documented shortcuts perform equivalent actions.
- [ ] Text editors accept literal h/j/k/l/x without navigation or destructive actions.
- [ ] Tab and Shift-Tab traverse every form field and action without trapping focus.
- [ ] Enter submits deliberately; Escape cancels editing without saving.
- [ ] Cancel destructive confirmation without changing data.
- [ ] No action is available exclusively by pointer.
- [ ] Mouse clicks, wheel scrolling and keyboard can be mixed without stale selection.
- [ ] Compact/default/wide panels show usable controls and readable errors.
- [ ] Closing/reopening preserves saved state and restores usable focus.

## Markets
- [ ] Add equity and cryptocurrency symbols; invalid/unknown symbol yields an actionable error.
- [ ] Reorder watchlist, reopen, verify exact ordering persisted.
- [ ] Open detail from list with Enter and return with keyboard.
- [ ] Add quantity with price only, date only, and date plus price; missing cost is not treated as zero.
- [ ] Record multiple lots; verify totals and P/L against fixture calculations.
- [ ] Watchlist sparklines and detail graph reflect returned data, not generated examples.
- [ ] Failed refresh preserves last valid quote and labels it stale.
- [ ] Remove selected asset only after confirmation.

## Monitor
- [ ] CPU/RAM graphs update with real samples while visible, without overlapping refreshes.
- [ ] Filter/sort processes while preserving selection by identity, not old row index.
- [ ] Exercise TERM only on a disposable process created for testing.
- [ ] KILL requires separate explicit confirmation and cannot silently replace TERM.
- [ ] Protected processes and other users' processes are rejected; no privilege elevation.
- [ ] Process exit/PID reuse between selection and confirmation cannot target an unrelated process.

## News
- [ ] Switch feeds, select headline, read detail and return using only keyboard.
- [ ] Add RSS and Atom sources; malformed XML and unsupported URL schemes show errors.
- [ ] Search, empty results, clear filter, restore visible selection.
- [ ] Open selected http(s) article in browser only after deliberate action.
- [ ] Add/remove custom source and verify persistence after reopening.
- [ ] One failed source does not erase successful feed results or cached articles.
- [ ] Untrusted feed content renders as text, not executable/rich remote content.

## Release gate
Unit tests, backend smoke tests and manifest validation are necessary but do not replace the interactive checks above. Record evidence and remaining failures before claiming keyboard-complete.
