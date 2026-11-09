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
    domain(A2:A6) series(B2:B6) title("Q4 totals") anchor(D2)
googlesheets addsheet,    spreadsheet("...") title("New tab")
```

## What it does

| Subcommand | Purpose | Excel analog |
|---|---|---|
| `import` | Read a range into the current dataset | `import excel` |
| `export` | Write the current dataset to a sheet | `export excel` |
| `put` | Place one value / formula / matrix at a cell | `putexcel` |
| `format` | Background colour, font, weight, number format | `putexcel ..., overwritefmt` |
| `addchart` | Insert a chart object (column / bar / stacked column / stacked bar / line / area / scatter / pie / donut) | n/a — Sheets-specific |
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
3. **APIs & Services → OAuth consent screen**: pick **External**, fill the required fields, add yourself (or anyone who will use the package) as a test user, and add the scopes the helper asks for: `https://www.googleapis.com/auth/spreadsheets`, `https://www.googleapis.com/auth/drive.file`, and `https://www.googleapis.com/auth/drive.metadata.readonly`.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** → Application type **Desktop app** → name it (e.g. "Stata googlesheets") → **Download JSON**.

### Step 2 — Wire it up (per machine)

1. Save the downloaded JSON somewhere stable. Suggested path:
   - macOS / Linux: `/Users/yourname/.config/stata-googlesheets/client.json` (`/home/yourname/...` on Linux)
   - Windows: `%APPDATA%\stata-googlesheets\client.json`

2. Tell Stata where to find it by setting `$GS_CLIENT` once. The right place is your `profile.do`, which Stata reads on every launch.

   On **macOS** the profile usually lives at `/Users/yourname/Documents/Stata/ado/personal/profile.do`. If you don't have one, create it. On **Windows** it sits next to the Stata executable (see `help profile`).

   The minimal addition is one line:
   ```stata
   global GS_CLIENT "/Users/yourname/.config/stata-googlesheets/client.json"
   ```
   Use the full path rather than one starting with `~`: operating systems, Stata versions and Python treat `~` differently. (googlesheets expands a leading `~` itself as a safety net, but a full path works everywhere.)

   Or, on macOS, if you keep the JSON in Google Drive so it's the same on every machine, find the Google Drive for desktop folder under `~/Library/CloudStorage`. On Linux or Windows (where the Drive letter varies), give the full path as in the one-line form above.
   ```stata
   if "`c(os)'" == "MacOSX" {
       local _gd_base "/Users/`c(username)'/Library/CloudStorage"
       local _gd_folders : dir "`_gd_base'" dirs "GoogleDrive-*"
       local _gd_folder  : word 1 of `_gd_folders'
       local _gd_folder  = subinstr(`"`_gd_folder'"', `"""', "", .)
       local _my_drive   `"`_gd_base'/`_gd_folder'/My Drive"'
       global GS_CLIENT  `"`_my_drive'/_credentials/client.json"'
   }
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
- **Python deps are auto-installed in a private venv.** On the very first call the package creates `.config/stata-googlesheets/venv` in your home folder (`%APPDATA%\stata-googlesheets\venv` on Windows) and pip-installs `google-api-python-client`, `google-auth`, and `google-auth-oauthlib` into it. The user's system Python is left untouched. Subsequent calls re-exec into the venv automatically.

### Trade-off

OAuth needs a browser **once per machine**. After that, the cached refresh token lets later runs on the same machine, including batch runs, proceed without a browser. While the OAuth consent screen is in Google's *Testing* status, those refresh tokens expire after about seven days; publishing the consent screen removes that limit. For machines with no display at all (cron servers, GitHub Actions), use a service account: create one in the Google Cloud console, download its JSON key, share the spreadsheet with the service account's e-mail address as an editor, and point `keyfile()` or `$GS_CLIENT` at the key. googlesheets recognizes a service-account key from the file itself and signs in with no browser and no token file.

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

`since(column=value)` keeps rows where the named column is `>=` the value. `column` is the header text as it appears in row 1 of the Sheet, or a 0-based column number. When both sides parse as numbers they are compared as numbers, and when both parse as dates or date-times they are compared as date-times; otherwise they are compared as text. The filter therefore stays correct when Google returns a timestamp with an unpadded hour (e.g. `2026-07-04 9:00:00`).

## Behaviour to know about

- **`import` needs `clear` when data are in memory**, as `import excel` does. Without it the command stops with error 4 ("no; data in memory would be lost"). The data in memory are replaced only after the Sheet has been read. With `firstrow`, variable names are lowercased, as `import delimited` does by default (`Timestamp` becomes `timestamp`). `import` stores `r(N)`, `r(k)`, `r(spreadsheet)` and `r(sheet)`.
- **`export` keeps string variables as text.** Numeric variables are written as numbers; a string variable such as a ZIP code `"00123"` keeps its leading zeros, and `"1e5"` or `"2026-01-01"` is stored as typed. A formula held in a string variable (`=SUM(...)`) is also written as text, not evaluated; use `put ..., formula()` to place a live formula. Numeric variables with value labels are written as their labels.
- **Floats keep their displayed precision.** A `float` variable is sent at the precision a float holds (3.58, not 3.5799999).
- **`format ..., range()`** may name its own tab (`'Auto'!A1:B2`); it is used as given.
- **`verbose`** prints the helper command and its result, and has the helper write its full reply (with any Python traceback) to a `.json` file next to its result file. Without `verbose` no such file is left in the temporary folder.
- **`put ..., matrix()` writes missing values as blank cells**, clearing whatever was in them. `value(.)` blanks a single cell.
- **`addchart` checks `type()`**: column, bar, stacked_column, stacked_bar, line, area, scatter, pie or donut. Anything else is an error.
- **Spreadsheet URLs** may be the plain `.../spreadsheets/d/<id>/edit` form or the multi-account `.../spreadsheets/u/1/d/<id>/edit` form; a bare id works too.
- **Tab names with apostrophes** (`Bob's data`) can be passed to `sheet()` as they are. `r(sheets)` joins tab names with `|`, so a `|` inside a tab name shows there as a space.

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
* Bar chart anchored at H10
googlesheets addchart using "..." , sheet("Auto") type(bar)        ///
    domain(A2:A6) series(B2:B6)                                    ///
    names("Avg price")                                             ///
    title("Domestic vs foreign: average sticker price")            ///
    legendpos(NONE)                                                ///
    targetsheet("Auto") anchor(H10) width(560) height(340)

* Donut with a 50% inner hole
googlesheets addchart using "..." , sheet("Auto") type(donut)      ///
    domain(A30:A34) series(B30:B34) piehole(0.5)                  ///
    title("Sector mix") legendpos(BOTTOM)                          ///
    targetsheet("Auto") anchor(D2)
```

Charts use the Sheets default theme unless you pass `colors("...|...")`. The `tx2036style` option is an internal house style used in the authors' own workflows (a navy Montserrat title and a matching palette). It is off unless you ask for it, and you do not need it; if the Montserrat font is unavailable, Sheets uses its default font and the chart is still made.

### Full worked example with `sysuse auto`

The shipped [test_googlesheets.do](test_googlesheets.do) is a 100-line end-to-end exercise using Stata's built-in `auto` dataset: it builds a fresh tab, brands the header, drops a correlation matrix off to the side, inserts four charts (column / scatter / bar / donut), reads the Sheet back, and tears the tab down. Set `$GS_CLIENT` and `$GS_TEST_SHEET` and run it against any Sheet you own.


## Author and license

Eric A. Booth, Sr Researcher, Texas 2036 (eric.a.booth@gmail.com). MIT-licensed. Built atop the Google Sheets API; not affiliated with or endorsed by Google.

 Thanks to Chen Samulsion, Marshall W. Garland, and Elizabeth Teas for debugging, review, and input. 
