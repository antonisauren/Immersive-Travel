if (Test-Path ImmersiveTravel.zip) {
	Remove-Item -Path ImmersiveTravel.zip
}

Compress-Archive -Path "00 Core", "01 BCOM", "02 Gnisis Docks", "03 TR", "99 Editor"  -DestinationPath "ImmersiveTravel.zip"