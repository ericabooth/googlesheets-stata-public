# googlesheets  - a Stata and Google Sheets connector

**Read, write, and edit Google Sheets directly from Stata.** It mirrors the `import excel` / `export excel` / `putexcel` family of Stata syntax, but interacts with live Google Sheets via the Sheets API (and Drive API if on Pro Google Account). Include commands to place figures and live Google Charts into Google Sheets. 

```stata
googlesheets ping,        spreadsheet("https://docs.google.com/spreadsheets/d/.../edit")
googlesheets list,        spreadsheet("...")
googlesheets import using "...", sheet("Sheet1") range("A1:F100") firstrow clear
googlesheets export using "...", sheet("Stata results") firstrow(variables)
googlesheets put    using "...", sheet("Summary") cell(A1) string("Final report")
googlesheets put    using "...", sheet("Summary") cell(B2) matrix(R)
googlesheets format using "...", sheet("Summary") range("A1:E1") bgcolor("#1B2D55") bold
googlesheets addchart using "...", sheet("Summary") type(column) ///
    domain(A2:A6) series(B2:B6) title("Q4 totals") tx2036style anchor(D2)
googlesheets addsheet,    spreadsheet("...") title("New tab")
```

## What it does

| Subcommand | Purpose | Excel analog |
|---|---|---|
| `import` | Read a range into the current dataset | `import excel` |
| `export` | Write the current dataset to a sheet | `export excel` |
| `put` | Place one value / formula / matrix at a cell | `putexcel` |
| `format` | Background colour, font, weight, number format | `putexcel ..., overwritefmt` |
| `addchart` | Insert a chart object (column / bar / line / area / scatter / pie / donut) | n/a — Sheets-specific |
| `list` | List the tab names | n/a |
| `addsheet` / `deletesheet` / `renamesheet` | Tab management | n/a |
| `ping` | OAuth / API connectivity check | n/a |
| `create` | Make a new spreadsheet in your Drive (returns its id / URL) | n/a |

## Why use it

- **No CSV round-trip.** Stata talks to the Sheet directly; no manual download / re-upload.
- **Form data, filtered at the source.** `since(Timestamp=2026-01-01)` and `tail(50)` pull just the new or most-recent rows from a Google Forms response sheet — useful when the full responses tab has thousands of rows.
- **Brand-styled output in one step.** `format ... bgcolor("#...") font("Montserrat") bold` applies the same brand styling you'd otherwise click through manually.

## Install

```stata
net install googlesheets, from("https://raw.githubusercontent.com/ericabooth/googlesheets-stata-public/main/") replace force
help googlesheets
```

The package ships `googlesheets.pkg` and `stata.toc` so Stata's installer picks up the ado files, the Python helper, and the helpfile in one call. No manual `adopath` step is needed.

## One-time auth setup

The package uses an **OAuth Desktop client** so calls run as your own Google identity — no per-sheet sharing required, and any Sheet you can open in your browser is accessible.

### Step 1 — Create the OAuth client (one time, any user)

1. Go to <https://console.cloud.google.com> and create a new project (any name).
2. **APIs & Services → Library**: enable **Google Sheets API** and **Google Drive API**.
3. **APIs & Services → OAuth consent screen**: pick **External**, fill the required fields, add yourself (or anyone who will use the package) as a test user, and grant the scopes `https://www.googleapis.com/auth/spreadsheets` and `https://www.googleapis.com/auth/drive`.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** → Application type **Desktop app** → name it (e.g. "Stata googlesheets") → **Download JSON**.

### Step 2 — Wire it up (per machine)

1. Save the downloaded JSON somewhere stable. Suggested path:
   - macOS / Linux: `~/.config/stata-googlesheets/client.json`
   - Windows: `%APPDATA%\stata-googlesheets\client.json`

2. Tell Stata where to find it by setting `$GS_CLIENT` once. The right place is your `profile.do`, which Stata reads on every launch.

   On **macOS** the profile usually lives at `~/Documents/Stata/ado/personal/profile.do`. If you don't have one, create it. On **Windows** it sits next to the Stata executable (see `help profile`).

   The minimal addition is one line:
   ```stata
   global GS_CLIENT "~/.config/stata-googlesheets/client.json"
   ```

   Or, if you keep the JSON in Google Drive so it's the same on every machine, auto-detect the mount point so the path stays correct cross-OS:
   ```stata
   if inlist("`c(os)'", "MacOSX", "Unix") {
       local _gd_base "/Users/`c(username)'/Library/CloudStorage"
       local _gd_folders : dir "`_gd_base'" dirs "GoogleDrive-*"
       local _gd_folder  : word 1 of `_gd_folders'
       local _gd_folder  = subinstr(`"`_gd_folder'"', `"""', "", .)
       local _my_drive   `"`_gd_base'/`_gd_folder'/My Drive"'
   }
   else if "`c(os)'" == "Windows" {
       local _my_drive "G:/My Drive"
   }
   global GS_CLIENT     `"`_my_drive'/_credentials/client.json"'
   global GS_TEST_SHEET "https://docs.google.com/spreadsheets/d/<your-id>/edit"
   ```

   `$GS_TEST_SHEET` is what the shipped `test_googlesheets.do` writes into — leave it out if you don't need the example to run unattended.

3. Run any `googlesheets` command. **The first time**, your browser will open a Google sign-in screen → pick the account that should own the API calls → click **Allow**. A refresh token is written next to the client JSON (`token.json`, file mode 0600). Token refresh is silent thereafter.

### Verifying the setup

After restarting Stata (or running `do <path-to-your-profile.do>` to reload the globals), confirm everything resolved:

```stata
display "$GS_CLIENT"                  // should print the JSON path
display fileexists("$GS_CLIENT")      // should print 1
googlesheets ping, spreadsheet("$GS_TEST_SHEET")
```

If `$GS_CLIENT` is empty after restart, your `profile.do` isn't being read — see `help profile` for the load order.

### What this buys you

- **No per-Sheet sharing.** OAuth uses your own Google identity, so the package can read or write any Sheet you can already open in your browser.
- **No long-lived secret in the JSON.** The downloaded file contains a public client ID, not a password. The actual credential is the per-user token in `token.json`.
- **Python deps are auto-installed in a private venv.** On the very first call the package creates `~/.config/stata-googlesheets/venv` and pip-installs `google-api-python-client`, `google-auth`, and `google-auth-oauthlib` into it. The user's system Python is left untouched. Subsequent calls re-exec into the venv automatically.

### Trade-off

OAuth needs a browser **once per machine**. That's fine for interactive work but blocks cron / scheduled / GitHub Actions runs that have no display. For those cases, swap in a Service Account JSON (same GCP project — **Credentials → Create credentials → Service account**, download JSON, share each target Sheet with the bot's email) and point `$GS_CLIENT` at it. The wrapper auto-detects which auth flow the JSON uses.

## Quick examples

### Pull the last 50 form responses

```stata
googlesheets import using "https://docs.google.com/spreadsheets/d/.../edit", ///
    sheet("Form Responses 1") firstrow clear tail(50)
list, abbrev(15) noobs
```

### Pull only responses received since a date

```stata
googlesheets import using "..." , sheet("Form Responses 1") firstrow clear ///
    since(Timestamp=2026-01-01)
```

`since(column=value)` keeps rows where the named column is `>=` the value. It compares dates and numbers as such rather than as text, so the filter stays correct even when Google returns a timestamp with an unpadded hour (e.g. `2026-07-04 9:00:00`), integers, or string codes.

### Create a fresh spreadsheet from Stata

```stata
googlesheets create, title("My report") sheettitle("Data")
display "`r(url)'"          // open the new sheet in a browser
global SS "`r(url)'"        // reuse it in every later command
```

`create` makes a brand-new spreadsheet in your Drive and returns its id in `r(id)` and its URL in `r(url)`, so a script can build a report from nothing without first opening a browser.

### Write a Stata summary table to a new tab

```stata
* Compute the summary you want to publish.
collapse (mean) outcome [pw=w1], by(group)

* Make a tab to write into, then push the data + variable names.
googlesheets addsheet, spreadsheet("..." ) title("Stata summary")
googlesheets export using "...", sheet("Stata summary") firstrow(variables)

* Brand the header row.
googlesheets format using "...", sheet("Stata summary") range("A1:Z1") ///
    bgcolor("#1B2D55") fgcolor("#FFFFFF") bold font("Montserrat") fontsize(12)
```

### Drop a regression coefficient matrix at B2

```stata
reg y x1 x2 x3
matrix B = r(table)
googlesheets put using "..." , sheet("Coefficients") cell(B2) matrix(B)
```

### Insert a chart from data already on the Sheet

```stata
* Bar chart, navy series colour, anchored at H10
googlesheets addchart using "..." , sheet("Auto") type(bar)        ///
    domain(A2:A6) series(B2:B6)                                    ///
    names("Avg price")                                             ///
    title("Domestic vs foreign: average sticker price")            ///
    tx2036style legendpos(NONE)                                    ///
    targetsheet("Auto") anchor(H10) width(560) height(340)

* Donut with a 50% inner hole
googlesheets addchart using "..." , sheet("Auto") type(donut)      ///
    domain(A30:A34) series(B30:B34) piehole(0.5)                  ///
    title("Sector mix") tx2036style legendpos(BOTTOM)              ///
    targetsheet("Auto") anchor(D2)
```

`tx2036style` applies a brand palette (`#1B2D55` / `#D44500` / `#2B6CB0` / `#6C7A8D` / `#7A9D54`) and a Montserrat navy title. Pass an explicit `colors("...|...")` to override, or omit `tx2036style` for Sheets' default theme.

### Full worked example with `sysuse auto`

The shipped [test_googlesheets.do](test_googlesheets.do) is a 100-line end-to-end exercise using Stata's built-in `auto` dataset: it builds a fresh tab, brands the header, drops a correlation matrix off to the side, inserts four charts (column / scatter / bar / donut), reads the Sheet back, and tears the tab down. Set `$GS_CLIENT` and `$GS_TEST_SHEET` and run it against any Sheet you own.

## Author and license

Eric A. Booth, Sr Researcher, Texas2036.org (eric.a.booth@gmail.com). MIT-licensed. Built atop the Google Sheets API; not affiliated with or endorsed by Google.
