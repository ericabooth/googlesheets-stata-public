*! test_googlesheets.do  v0.2.0
*!
*! End-to-end exercise of the googlesheets package against a real Google
*! Sheet you own.  Uses Stata's built-in sysuse auto so the example is
*! reproducible on any machine.
*!
*! Walks through:
*!   ping  ->  list  ->  addsheet  ->  export  ->  format header  ->
*!   put (string / value / matrix)  ->  addchart x 4  ->
*!   import (read back)  ->  deletesheet
*!
*! Before running:
*!   1. Set $GS_CLIENT to your OAuth Desktop client JSON path.
*!         global GS_CLIENT "~/.config/stata-googlesheets/client.json"
*!   2. Set $GS_TEST_SHEET to a spreadsheet URL or ID you can edit.
*!         global GS_TEST_SHEET "https://docs.google.com/spreadsheets/d/.../edit"
*!
*! The first call opens your browser for OAuth consent.  Click Allow once
*! and the token cache handles every future call silently.

version 17.0
clear all
set more off

if "$GS_CLIENT" == "" {
    display as error "Set \$GS_CLIENT to your OAuth Desktop client JSON path first."
    exit 198
}
if "$GS_TEST_SHEET" == "" {
    display as error "Set \$GS_TEST_SHEET to the spreadsheet you want to test against."
    exit 198
}

local SS "$GS_TEST_SHEET"


*=============================================================================
* (1) Ping -- confirm OAuth works + show what's already in the spreadsheet
*=============================================================================
googlesheets ping, spreadsheet("`SS'")


*=============================================================================
* (2) Build the working dataset (Stata's auto)
*=============================================================================
sysuse auto, clear
describe, short


*=============================================================================
* (3) Make a fresh tab + write the data with variable names as row 1
*=============================================================================
capture googlesheets deletesheet, spreadsheet("`SS'") title("Auto")
googlesheets addsheet, spreadsheet("`SS'") title("Auto")
googlesheets export using "`SS'", sheet("Auto") firstrow(variables)


*=============================================================================
* (4) Brand the header row -- navy fill, white Montserrat 12 bold
*=============================================================================
googlesheets format using "`SS'", sheet("Auto") range("A1:M1") ///
    bgcolor("#1B2D55") fgcolor("#FFFFFF") bold font("Montserrat") fontsize(12)


*=============================================================================
* (5) Number-format the price column as US currency
*=============================================================================
googlesheets format using "`SS'", sheet("Auto") range("D2:D75") numfmt(`""$"#,##0"')


*=============================================================================
* (6) Surgical placement: title block + run timestamp + Stata summary stats
*=============================================================================
googlesheets put using "`SS'", sheet("Auto") cell(O1) string("Auto data summary")
googlesheets put using "`SS'", sheet("Auto") cell(O2)                          ///
    string("Run date: `=c(current_date)'")

summarize price
googlesheets put using "`SS'", sheet("Auto") cell(O3) value(`=r(mean)')
googlesheets put using "`SS'", sheet("Auto") cell(O4) formula("=AVERAGE(D2:D75)")
googlesheets put using "`SS'", sheet("Auto") cell(O5) formula("=STDEV(D2:D75)")


*=============================================================================
* (7) Drop a Stata correlation matrix at O7:R10
*=============================================================================
correlate price mpg weight length
matrix C = r(C)
googlesheets put using "`SS'", sheet("Auto") cell(O7) matrix(C)


*=============================================================================
* (8) Insert four charts on the same tab
*=============================================================================

* (8a) Column chart of average price by foreign / domestic
preserve
collapse (mean) price, by(foreign)
gen sortkey = _n + 100      // any large offset so we don't overwrite earlier cols
* Write the small grouped table off to the side first.
local _r = 100
googlesheets put using "`SS'", sheet("Auto") cell(W`_r')     string("foreign")
googlesheets put using "`SS'", sheet("Auto") cell(X`_r')     string("avg_price")
local _r = `_r' + 1
forvalues i = 1/`=_N' {
    googlesheets put using "`SS'", sheet("Auto") cell(W`_r') value(`=foreign[`i']')
    googlesheets put using "`SS'", sheet("Auto") cell(X`_r') value(`=price[`i']')
    local ++_r
}
restore

googlesheets addchart using "`SS'", sheet("Auto") type(column)                ///
    domain(W101:W102) series(X101:X102)                                        ///
    names("Avg price")                                                         ///
    title("Domestic vs foreign - average sticker price")                       ///
    xlabel("foreign indicator") ylabel("Price (USD)")                          ///
    tx2036style legendpos(NONE)                                                ///
    targetsheet("Auto") anchor(O15) width(560) height(340)

* (8b) Scatter -- price vs mpg
googlesheets addchart using "`SS'", sheet("Auto") type(scatter)                ///
    domain(H2:H75) series(D2:D75)                                              ///
    names("Price")                                                             ///
    title("Price vs mpg")                                                      ///
    xlabel("mpg") ylabel("Price (USD)")                                        ///
    tx2036style legendpos(NONE)                                                ///
    targetsheet("Auto") anchor(O35) width(560) height(340)

* (8c) Bar (horizontal) -- top 10 by price
preserve
keep if _n <= 10
gsort -price
local _r = 200
googlesheets put using "`SS'", sheet("Auto") cell(W`_r') string("make")
googlesheets put using "`SS'", sheet("Auto") cell(X`_r') string("price")
local _r = `_r' + 1
forvalues i = 1/`=_N' {
    googlesheets put using "`SS'", sheet("Auto") cell(W`_r') string("`=make[`i']'")
    googlesheets put using "`SS'", sheet("Auto") cell(X`_r') value(`=price[`i']')
    local ++_r
}
restore

googlesheets addchart using "`SS'", sheet("Auto") type(bar)                    ///
    domain(W201:W210) series(X201:X210)                                        ///
    names("Price")                                                             ///
    title("Top 10 makes by price (first 10 rows)")                              ///
    tx2036style legendpos(NONE)                                                ///
    targetsheet("Auto") anchor(O60) width(560) height(420)

* (8d) Donut -- repair record share
preserve
contract rep78
local _r = 300
googlesheets put using "`SS'", sheet("Auto") cell(W`_r') string("rep78")
googlesheets put using "`SS'", sheet("Auto") cell(X`_r') string("count")
local _r = `_r' + 1
forvalues i = 1/`=_N' {
    googlesheets put using "`SS'", sheet("Auto") cell(W`_r') value(`=rep78[`i']')
    googlesheets put using "`SS'", sheet("Auto") cell(X`_r') value(`=_freq[`i']')
    local ++_r
}
restore

googlesheets addchart using "`SS'", sheet("Auto") type(donut)                  ///
    domain(W301:W305) series(X301:X305) piehole(0.5)                          ///
    title("Repair record distribution (rep78)")                                 ///
    tx2036style legendpos(BOTTOM)                                              ///
    targetsheet("Auto") anchor(O90) width(420) height(340)


*=============================================================================
* (9) Read the Sheet back into Stata for a round-trip QA check
*=============================================================================
googlesheets import using "`SS'", sheet("Auto") range("A1:M75") firstrow clear

display as result _n "Round-tripped data:"
list make price mpg foreign in 1/5, abbrev(15) noobs


*=============================================================================
* (10) Clean up
*=============================================================================
googlesheets deletesheet, spreadsheet("`SS'") title("Auto")

display as result _n "==> test_googlesheets.do complete."
