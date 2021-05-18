# Secondary functions for vrni-aws-create-flow-logs.ps1

function Compare-Hashtable(
  [Hashtable]$ReferenceObject,
  [Hashtable]$DifferenceObject
) {
  # Creates a result object.
  function result( [string]$side ) {
    New-Object PSObject -Property @{
      'InputPath'= "$path$key";
      'SideIndicator' = $side;
      'ReferenceValue' = $refValue;
      'DifferenceValue' = $difValue;
    }
  }

  # Recursively compares two hashtables.
  function core( [string]$path, [Hashtable]$ref, [Hashtable]$dif ) {
    # Hold on to keys from the other object that are not in the reference.
    $nonrefKeys = New-Object 'System.Collections.Generic.HashSet[string]'
    $dif.Keys | foreach { [void]$nonrefKeys.Add( $_ ) }

    # Test each key in the reference with that in the other object.
    foreach( $key in $ref.Keys ) {
      [void]$nonrefKeys.Remove( $key )
      $refValue = $ref.$key
      $difValue = $dif.$key

      if( -not $dif.ContainsKey( $key ) ) {
        result '<='
      }
      elseif( $refValue -is [hashtable] -and $difValue -is [hashtable] ) {
        core "$path$key." $refValue $difValue
      }
      #elseif( $refValue -ne $difValue ) {
      #  result '<>'
      #}
    }

    # Show all keys in the other object not in the reference.
    $refValue = $null
    foreach( $key in $nonrefKeys ) {
      $difValue = $dif.$key
      result '=>'
    }
  }

  core '' $ReferenceObject $DifferenceObject
}

Function My-Logger(
    [String]$message,
    [String]$textcolor = "green",
    [bool]$Verbose = $False
)
{
    # Don't print verbose messages if not requested
    if($Verbose -eq $True -And $global:VerboseOutput -eq $False) {
        return
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh-mm-ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor $textcolor " $message"
}