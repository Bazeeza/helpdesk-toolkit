function Get-ReportStyleSheet {
    <#
    .SYNOPSIS
        Returns the CSS embedded in the HTML report: dark and light themes,
        a theme switch without JavaScript, and a print layout.

    .DESCRIPTION
        Private helper of the HTML report. The style sheet is written inside
        the page (<style>), so the report is one self-contained file: it
        opens the same way from a ticket attachment, an e-mail or a USB key,
        without Internet access and without any external font or script.

        Colours are CSS variables defined twice, once per theme:

          dark   the default, on #070d1c
          light  used when Windows or the browser asks for a light theme
                 (prefers-color-scheme), and always when printing

        The "Switch theme" label of the page toggles a hidden checkbox; the
        :has() selector then swaps the two palettes. Browsers without :has()
        simply keep the theme of the system. No JavaScript is needed, so the
        report also works where scripts are blocked.

        Every status colour reaches a contrast of at least 4.5:1 on its
        background (WCAG AA for normal text), and every status is also
        written as a word, never shown by colour alone.

    .EXAMPLE
        Get-ReportStyleSheet

        Returns the CSS text, to be placed inside <style></style>.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $dark = [ordered]@{
        'color-scheme' = 'dark'
        '--bg'         = '#070d1c'
        '--surface'    = '#0d1529'
        '--inset'      = '#070d1c'
        '--border'     = '#1f2a44'
        '--text'       = '#e6edf7'
        '--muted'      = '#8b95a7'
        '--accent'     = '#2b9dff'
        '--brand'      = '#c792ea'
        '--ok'         = '#3fe0a0'
        '--warn'       = '#ffb454'
        '--crit'       = '#ff6b81'
    }
    $light = [ordered]@{
        'color-scheme' = 'light'
        '--bg'         = '#f4f6fb'
        '--surface'    = '#ffffff'
        '--inset'      = '#f4f6fb'
        '--border'     = '#d5dbe7'
        '--text'       = '#0f172a'
        '--muted'      = '#556070'
        '--accent'     = '#0b6bcb'
        '--brand'      = '#7b3fb0'
        '--ok'         = '#0a7d55'
        '--warn'       = '#9a5b00'
        '--crit'       = '#c0263d'
    }

    $toBlock = {
        param([string]$Selector, [System.Collections.IDictionary]$Palette)
        $lines = foreach ($key in $Palette.Keys) { '  {0}: {1};' -f $key, $Palette[$key] }
        "$Selector {`n$($lines -join "`n")`n}"
    }

    $checked = ':root:has(#theme-switch:checked)'
    $themes = @(
        '/* Dark by default, light when the system asks for it */'
        & $toBlock ':root' $dark
        '@media (prefers-color-scheme: light) {'
        & $toBlock ':root' $light
        '}'
        '/* The switch shows the other theme */'
        & $toBlock $checked $light
        '@media (prefers-color-scheme: light) {'
        & $toBlock $checked $dark
        '}'
        '/* Paper is white: always print the light theme */'
        '@media print {'
        & $toBlock ":root, $checked" $light
        '}'
    ) -join "`n"

    $layout = @'
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body { margin: 0; background: var(--bg); color: var(--text); font: 15px/1.5 "Segoe UI", system-ui, -apple-system, Roboto, "Helvetica Neue", Arial, sans-serif; }
.page { max-width: 1120px; margin: 0 auto; padding: 32px 24px 48px; }
a { color: var(--accent); }
.mono, code { font-family: "Cascadia Mono", Consolas, "Courier New", monospace; font-size: 0.92em; }

/* Header */
.report-header { display: grid; grid-template-columns: 1fr auto; gap: 4px 16px; padding-bottom: 18px; border-bottom: 2px solid var(--brand); }
.brand { color: var(--brand); font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; font-size: 12px; }
h1 { margin: 0; font-size: 28px; line-height: 1.2; }
.meta { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: 6px 28px; margin: 10px 0 0; }
.meta div { display: flex; gap: 8px; }
.meta dt { color: var(--muted); }
.meta dd { margin: 0; font-weight: 600; }
.theme-input { position: absolute; opacity: 0; width: 1px; height: 1px; }
.theme-switch { align-self: start; grid-column: 2; grid-row: 1 / span 2; cursor: pointer; user-select: none; padding: 6px 14px; border: 1px solid var(--border); border-radius: 999px; color: var(--muted); font-size: 13px; background: var(--surface); }
.theme-switch:hover { color: var(--text); border-color: var(--accent); }
.theme-input:focus-visible + .page .theme-switch { outline: 2px solid var(--accent); outline-offset: 2px; }

/* Table of contents and summary cards */
.toc { display: flex; flex-wrap: wrap; gap: 8px 18px; margin: 18px 0 0; font-size: 14px; }
.toc a { text-decoration: none; }
.toc a:hover { text-decoration: underline; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 16px; margin: 22px 0 8px; }
.card { background: var(--surface); border: 1px solid var(--border); border-left: 4px solid var(--accent); border-radius: 8px; padding: 14px 16px; }
.card-ok { border-left-color: var(--ok); }
.card-warn { border-left-color: var(--warn); }
.card-crit { border-left-color: var(--crit); }
.card-muted { border-left-color: var(--muted); }
.card-title { display: flex; justify-content: space-between; align-items: center; gap: 8px; color: var(--muted); font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; }
.card-value { margin-top: 6px; font-size: 18px; font-weight: 600; }
.card-detail { margin-top: 2px; color: var(--muted); font-size: 14px; }

/* Sections */
section { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 20px 22px; margin: 20px 0; }
h2 { display: flex; align-items: center; flex-wrap: wrap; gap: 12px; margin: 0 0 14px; font-size: 20px; }
h3 { margin: 22px 0 8px; color: var(--muted); font-size: 13px; text-transform: uppercase; letter-spacing: 0.06em; }
.callout { margin: 0 0 8px; padding: 10px 14px; border-left: 4px solid var(--accent); border-radius: 4px; background: var(--inset); }
.callout-ok { border-left-color: var(--ok); }
.callout-warn { border-left-color: var(--warn); }
.callout-crit { border-left-color: var(--crit); }
.callout-muted { border-left-color: var(--muted); }
.issues { margin: 0; padding-left: 20px; }
.issues li { margin: 2px 0; }
.empty, .missing, .note { color: var(--muted); }
.missing { font-style: italic; }
.note { font-size: 14px; margin: 10px 0 0; }

/* Tables */
.table-wrap { overflow-x: auto; }
table.report { width: 100%; border-collapse: collapse; font-size: 14px; }
table.report th, table.report td { text-align: left; vertical-align: top; padding: 7px 10px; border-bottom: 1px solid var(--border); }
table.report th { color: var(--muted); font-weight: 600; white-space: nowrap; }
table.report tbody tr:hover { background: var(--inset); }
table.facts td:first-child { width: 30%; color: var(--muted); }
table.facts td:last-child { font-weight: 600; overflow-wrap: anywhere; }

/* Status badges and percentage bars */
.badge { display: inline-block; padding: 1px 10px; border: 1px solid currentColor; border-radius: 999px; font-size: 12px; font-weight: 700; letter-spacing: 0.03em; line-height: 1.6; white-space: nowrap; }
.badge-ok { color: var(--ok); }
.badge-warn { color: var(--warn); }
.badge-crit { color: var(--crit); }
.badge-muted { color: var(--muted); }
.meter { display: inline-block; vertical-align: middle; width: 90px; height: 8px; border-radius: 4px; background: var(--border); overflow: hidden; }
.meter span { display: block; height: 100%; background: var(--accent); }

footer { margin-top: 30px; color: var(--muted); font-size: 13px; }

@media (max-width: 640px) {
  .page { padding: 20px 14px 32px; }
  .report-header { grid-template-columns: 1fr; }
  .theme-switch { grid-column: 1; grid-row: auto; justify-self: start; }
  table.facts td:first-child { width: 42%; }
}

@media print {
  body { font-size: 12px; }
  .page { max-width: none; padding: 0; }
  .theme-switch, .toc { display: none; }
  .card, .callout { break-inside: avoid; }
  table.report tr { break-inside: avoid; }
  .meter { border: 1px solid var(--muted); }
}
'@

    $themes + "`n`n" + $layout.Trim()
}
