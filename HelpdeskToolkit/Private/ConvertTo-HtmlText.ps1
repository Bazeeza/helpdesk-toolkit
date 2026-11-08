function ConvertTo-HtmlText {
    <#
    .SYNOPSIS
        Turns any value into text that is safe to put inside an HTML page.

    .DESCRIPTION
        Private helper of the HTML report. Every value written in the report
        goes through this function, without exception, because the values
        come from the computer: a program name, a disk label or a DNS error
        message can contain "<", "&" or quotes, and an installer can write
        any text it wants in the registry. Encoding them means such text is
        displayed, never interpreted as HTML.

        The value is first converted to readable text, the same way on every
        workstation:

          $null             empty text
          DateTime          2026-11-08 14:05 (invariant culture)
          Boolean           Yes or No
          numbers           dot as decimal separator (invariant culture)
          collections       the items joined with ", ", empty items skipped
          anything else     its ToString() value

        then encoded with System.Net.WebUtility.HtmlEncode, available in
        Windows PowerShell 5.1 and PowerShell 7 without loading System.Web.

    .PARAMETER Value
        The value to convert. Accepts $null, an empty string and pipeline
        input.

    .EXAMPLE
        ConvertTo-HtmlText -Value 'Tools <x64> & more'
        Tools &lt;x64&gt; &amp; more

    .EXAMPLE
        ConvertTo-HtmlText -Value @('192.0.2.53', '192.0.2.54')
        192.0.2.53, 192.0.2.54
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value
    )

    begin {
        $culture = [System.Globalization.CultureInfo]::InvariantCulture

        # Plain text first, encoded once at the end: encoding each item of a
        # collection and then the joined text would encode "&" twice
        function ConvertTo-PlainText {
            param([object]$Item)

            if ($null -eq $Item) {
                return ''
            }
            if ($Item -is [datetime]) {
                return $Item.ToString('yyyy-MM-dd HH:mm', $culture)
            }
            if ($Item -is [bool]) {
                if ($Item) { return 'Yes' }
                return 'No'
            }
            if ($Item -is [string]) {
                return $Item
            }
            if ($Item -is [System.Collections.IEnumerable]) {
                $parts = foreach ($element in $Item) {
                    $text = ConvertTo-PlainText -Item $element
                    if ($text) { $text }
                }
                return (@($parts) -join ', ')
            }
            if ($Item -is [System.IFormattable]) {
                return $Item.ToString($null, $culture)
            }
            # Objects of the module may carry their own ToString script method
            return [string]$Item
        }
    }

    process {
        [System.Net.WebUtility]::HtmlEncode((ConvertTo-PlainText -Item $Value))
    }
}
