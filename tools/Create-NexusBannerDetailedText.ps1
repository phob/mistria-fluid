param(
    [string]$InputPath = "C:\Users\pho\Source\mistria-fluid\nexus\FieldsOfMistriaBase.png",
    [string]$OutputPath = "C:\Users\pho\Source\mistria-fluid\nexus\FieldsOfMistria-ARPG-Movement-V2.4-Banner-DetailedText.png",
    [string]$FontPath = (Join-Path $PSScriptRoot "fonts\BowlbyOneSC-Regular.ttf"),
    [string]$TitleText = "ARPG MOVEMENT",
    [string]$VersionText = "V2.4",
    [string]$FeatureText = "AUTO-SWAPPING TOOLS",
    [string]$SupportText = "STEAM DECK + CONTROLLER SUPPORT",
    [ValidateRange(1, 8)]
    [int]$TextPixelSize = 3
)

Add-Type -AssemblyName System.Drawing

function New-OpacityAttributes([float]$Opacity) {
    $matrix = New-Object System.Drawing.Imaging.ColorMatrix
    $matrix.Matrix00 = 1.0
    $matrix.Matrix11 = 1.0
    $matrix.Matrix22 = 1.0
    $matrix.Matrix33 = $Opacity
    $matrix.Matrix44 = 1.0
    $attributes = New-Object System.Drawing.Imaging.ImageAttributes
    $attributes.SetColorMatrix($matrix)
    return $attributes
}

function Draw-ImageOpacity(
    [System.Drawing.Graphics]$Graphics,
    [System.Drawing.Bitmap]$Image,
    [int]$X,
    [int]$Y,
    [float]$Opacity
) {
    $attributes = New-OpacityAttributes $Opacity
    $destination = New-Object System.Drawing.Rectangle($X, $Y, $Image.Width, $Image.Height)
    $Graphics.DrawImage(
        $Image,
        $destination,
        0,
        0,
        $Image.Width,
        $Image.Height,
        [System.Drawing.GraphicsUnit]::Pixel,
        $attributes
    )
    $attributes.Dispose()
}

function Draw-PixelDot([System.Drawing.Graphics]$Graphics, [int]$CenterX, [int]$CenterY) {
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $Graphics.FillRectangle($white, $CenterX - 4, $CenterY - 2, 8, 4)
    $Graphics.FillRectangle($white, $CenterX - 2, $CenterY - 4, 4, 8)
    $white.Dispose()
}

function Add-ReferenceText(
    [System.Drawing.Graphics]$ShadowGraphics,
    [System.Drawing.Graphics]$HardGraphics,
    [System.Drawing.Graphics]$FaceMaskGraphics,
    [string]$Text,
    [System.Drawing.FontFamily]$FontFamily,
    [float]$EmSize,
    [float]$Top,
    [float]$CanvasWidth,
    [float]$OutlineWidth,
    [float]$HorizontalScale = 1.0,
    [float]$VerticalScale = 1.0,
    [float]$HorizontalOffset = 0.0,
    [float]$WordGap = 0.0
) {
    $format = New-Object System.Drawing.StringFormat([System.Drawing.StringFormat]::GenericTypographic)
    $format.Alignment = [System.Drawing.StringAlignment]::Near
    $format.LineAlignment = [System.Drawing.StringAlignment]::Near

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($WordGap -gt 0 -and $Text.Contains(" ")) {
        $wordLeft = [float]0
        foreach ($word in $Text.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)) {
            $wordPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $wordPath.AddString(
                $word,
                $FontFamily,
                [int][System.Drawing.FontStyle]::Regular,
                $EmSize,
                (New-Object System.Drawing.PointF(0, $Top)),
                $format
            )
            $wordBounds = $wordPath.GetBounds()
            $wordMatrix = New-Object System.Drawing.Drawing2D.Matrix
            $wordMatrix.Translate(($wordLeft - $wordBounds.Left), 0)
            $wordPath.Transform($wordMatrix)
            $path.AddPath($wordPath, $false)
            $wordLeft += $wordBounds.Width + $WordGap
            $wordMatrix.Dispose()
            $wordPath.Dispose()
        }
    }
    else {
        $path.AddString(
            $Text,
            $FontFamily,
            [int][System.Drawing.FontStyle]::Regular,
            $EmSize,
            (New-Object System.Drawing.PointF(0, $Top)),
            $format
        )
    }

    $bounds = $path.GetBounds()
    if ($HorizontalScale -ne 1.0 -or $VerticalScale -ne 1.0) {
        $shapeMatrix = [System.Drawing.Drawing2D.Matrix]::new(
            $HorizontalScale,
            0,
            0,
            $VerticalScale,
            ($bounds.Left * (1.0 - $HorizontalScale)),
            ($bounds.Top * (1.0 - $VerticalScale))
        )
        $path.Transform($shapeMatrix)
        $shapeMatrix.Dispose()
        $bounds = $path.GetBounds()
    }

    $centerMatrix = New-Object System.Drawing.Drawing2D.Matrix
    $centerMatrix.Translate(
        ((($CanvasWidth - $bounds.Width) / 2.0) - $bounds.X + $HorizontalOffset),
        0
    )
    $path.Transform($centerMatrix)
    $bounds = $path.GetBounds()

    # The reference keeps its broad drop shadow smooth. It is drawn directly
    # at output resolution and never passes through the pixel grid.
    $shadowPath = [System.Drawing.Drawing2D.GraphicsPath]$path.Clone()
    $shadowMatrix = New-Object System.Drawing.Drawing2D.Matrix
    $shadowMatrix.Translate(7, 11)
    $shadowPath.Transform($shadowMatrix)
    $haloLayers = @(
        @{ ExtraWidth = 19; Alpha = 18 },
        @{ ExtraWidth = 15; Alpha = 26 },
        @{ ExtraWidth = 11; Alpha = 38 },
        @{ ExtraWidth = 7; Alpha = 56 }
    )
    foreach ($haloLayer in $haloLayers) {
        $haloPen = New-Object System.Drawing.Pen(
            [System.Drawing.Color]::FromArgb($haloLayer.Alpha, 22, 16, 25),
            ($OutlineWidth + $haloLayer.ExtraWidth)
        )
        $haloPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $ShadowGraphics.DrawPath($haloPen, $shadowPath)
        $haloPen.Dispose()
    }
    $shadowBrush = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(105, 36, 24, 35)
    )
    $ShadowGraphics.FillPath($shadowBrush, $shadowPath)

    # The extrusion and outline form the hard text treatment and are
    # pixelated together. The face is captured separately as an alpha mask so
    # its gradient can remain smooth inside the pixel-stepped silhouette.
    $depthPath = [System.Drawing.Drawing2D.GraphicsPath]$path.Clone()
    $depthMatrix = New-Object System.Drawing.Drawing2D.Matrix
    $depthMatrix.Translate(3, 6)
    $depthPath.Transform($depthMatrix)
    $depthPen = New-Object System.Drawing.Pen(
        [System.Drawing.Color]::FromArgb(255, 38, 23, 29),
        ($OutlineWidth + 4)
    )
    $depthPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $HardGraphics.DrawPath($depthPen, $depthPath)
    $depthBrush = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 183, 73, 22)
    )
    $HardGraphics.FillPath($depthBrush, $depthPath)

    $outlinePen = New-Object System.Drawing.Pen(
        [System.Drawing.Color]::FromArgb(255, 25, 19, 27),
        $OutlineWidth
    )
    $outlinePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $HardGraphics.DrawPath($outlinePen, $path)

    $faceMaskBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $FaceMaskGraphics.FillPath($faceMaskBrush, $path)

    $faceMaskBrush.Dispose()
    $outlinePen.Dispose()
    $depthBrush.Dispose()
    $depthPen.Dispose()
    $depthMatrix.Dispose()
    $depthPath.Dispose()
    $shadowBrush.Dispose()
    $shadowMatrix.Dispose()
    $shadowPath.Dispose()
    $centerMatrix.Dispose()
    $path.Dispose()
    $format.Dispose()

    return [pscustomobject]@{
        Top = $bounds.Top
        Bottom = $bounds.Bottom
    }
}

function New-GradientFaceBitmap(
    [System.Drawing.Bitmap]$PixelMask,
    [int]$CanvasWidth,
    [int]$CanvasHeight,
    [int]$PixelSize,
    [object[]]$Bands
) {
    $face = New-Object System.Drawing.Bitmap(
        $CanvasWidth,
        $CanvasHeight,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $maskRect = New-Object System.Drawing.Rectangle(0, 0, $PixelMask.Width, $PixelMask.Height)
    $faceRect = New-Object System.Drawing.Rectangle(0, 0, $CanvasWidth, $CanvasHeight)
    $maskData = $PixelMask.LockBits(
        $maskRect,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $faceData = $face.LockBits(
        $faceRect,
        [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    $maskByteCount = [Math]::Abs($maskData.Stride) * $PixelMask.Height
    $faceByteCount = [Math]::Abs($faceData.Stride) * $CanvasHeight
    $maskPixels = [byte[]]::new($maskByteCount)
    $facePixels = [byte[]]::new($faceByteCount)
    [System.Runtime.InteropServices.Marshal]::Copy(
        $maskData.Scan0,
        $maskPixels,
        0,
        $maskByteCount
    )

    $rowActive = [bool[]]::new($CanvasHeight)
    $rowRed = [byte[]]::new($CanvasHeight)
    $rowGreen = [byte[]]::new($CanvasHeight)
    $rowBlue = [byte[]]::new($CanvasHeight)
    foreach ($band in $Bands) {
        $top = [Math]::Max(0, [int][Math]::Floor($band.Top))
        $bottom = [Math]::Min($CanvasHeight - 1, [int][Math]::Ceiling($band.Bottom))
        $height = [Math]::Max(1.0, $band.Bottom - $band.Top)
        for ($y = $top; $y -le $bottom; $y++) {
            $t = [Math]::Max(0.0, [Math]::Min(1.0, (($y - $band.Top) / $height)))
            $red = 255 + ((240 - 255) * $t)
            $green = 229 + ((145 - 229) * $t)
            $blue = 76 + ((28 - 76) * $t)

            $highlightProgress = $t / 0.48
            if ($highlightProgress -lt 1.0) {
                $highlightAlpha = (32.0 / 255.0) * (1.0 - $highlightProgress)
                $red = $red + ((255 - $red) * $highlightAlpha)
                $green = $green + ((255 - $green) * $highlightAlpha)
                $blue = $blue + ((226 - $blue) * $highlightAlpha)
            }

            $rowActive[$y] = $true
            $rowRed[$y] = [byte][Math]::Round($red)
            $rowGreen[$y] = [byte][Math]::Round($green)
            $rowBlue[$y] = [byte][Math]::Round($blue)
        }
    }

    for ($y = 0; $y -lt $CanvasHeight; $y++) {
        if (-not $rowActive[$y]) {
            continue
        }

        $maskY = [Math]::Min([int]($y / $PixelSize), $PixelMask.Height - 1)
        if ($maskData.Stride -ge 0) {
            $maskRow = $maskY * $maskData.Stride
        }
        else {
            $maskRow = ($PixelMask.Height - 1 - $maskY) * (-$maskData.Stride)
        }
        if ($faceData.Stride -ge 0) {
            $faceRow = $y * $faceData.Stride
        }
        else {
            $faceRow = ($CanvasHeight - 1 - $y) * (-$faceData.Stride)
        }

        for ($x = 0; $x -lt $CanvasWidth; $x++) {
            $maskX = [Math]::Min([int]($x / $PixelSize), $PixelMask.Width - 1)
            $maskOffset = $maskRow + ($maskX * 4)
            $alpha = $maskPixels[$maskOffset + 3]
            if ($alpha -eq 0) {
                continue
            }

            $faceOffset = $faceRow + ($x * 4)
            $facePixels[$faceOffset] = $rowBlue[$y]
            $facePixels[$faceOffset + 1] = $rowGreen[$y]
            $facePixels[$faceOffset + 2] = $rowRed[$y]
            $facePixels[$faceOffset + 3] = $alpha
        }
    }

    [System.Runtime.InteropServices.Marshal]::Copy(
        $facePixels,
        0,
        $faceData.Scan0,
        $faceByteCount
    )
    $face.UnlockBits($faceData)
    $PixelMask.UnlockBits($maskData)

    return $face
}

$base = [System.Drawing.Bitmap]::FromFile($InputPath)
if ($base.Width -ne 1920 -or $base.Height -ne 1080) {
$base.Dispose()
throw "Input must be exactly 1920x1080."
}

$cloneRect = New-Object System.Drawing.Rectangle(0, 0, 1920, 1080)
$output = $base.Clone($cloneRect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($output)
$graphics.PageUnit = [System.Drawing.GraphicsUnit]::Pixel
$graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

# Reproduce the approved movement overlay from exact source pixels.
$sourceX = 1000
$sourceY = 430
$sourceWidth = 76
$sourceHeight = 126
$sprite = New-Object System.Drawing.Bitmap($sourceWidth, $sourceHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $sourceHeight; $y++) {
for ($x = 0; $x -lt $sourceWidth; $x++) {
    $color = $base.GetPixel($sourceX + $x, $sourceY + $y)
    $hex = "{0:X2}{1:X2}{2:X2}" -f $color.R, $color.G, $color.B
    if ($hex -eq "76BA94" -or $hex -eq "4A9A68") {
        $sprite.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
    }
    else {
        $sprite.SetPixel($x, $y, $color)
    }
}
}

$veil = New-Object System.Drawing.Bitmap($sourceWidth, $sourceHeight, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt $sourceHeight; $y++) {
for ($x = 0; $x -lt $sourceWidth; $x++) {
    if ($sprite.GetPixel($x, $y).A -gt 0) {
        $veil.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(204, 118, 186, 148))
    }
}
}
$graphics.DrawImage(
    $veil,
    (New-Object System.Drawing.Rectangle($sourceX, $sourceY, $sourceWidth, $sourceHeight)),
    0,
    0,
    $sourceWidth,
    $sourceHeight,
    [System.Drawing.GraphicsUnit]::Pixel
)

$stages = @(
    @{ X = 1034; Y = 444; Opacity = [float]0.35 },
    @{ X = 1069; Y = 461; Opacity = [float]0.50 },
    @{ X = 1108; Y = 477; Opacity = [float]0.70 },
    @{ X = 1148; Y = 495; Opacity = [float]1.00 }
)
foreach ($stage in $stages) {
    Draw-ImageOpacity $graphics $sprite $stage.X $stage.Y $stage.Opacity
}

for ($i = 0; $i -le 10; $i++) {
    $t = $i / 10.0
    $oneMinusT = 1.0 - $t
    $x = [int][Math]::Round(($oneMinusT * $oneMinusT * 1038) + (2 * $oneMinusT * $t * 1105) + ($t * $t * 1183))
    $y = [int][Math]::Round(($oneMinusT * $oneMinusT * 555) + (2 * $oneMinusT * $t * 596) + ($t * $t * 619))
    Draw-PixelDot $graphics $x $y
}

# Pixelate the hard text treatment as one layer. The soft shadow is rendered
# directly onto the output first, so it retains the smooth falloff visible in
# the reference instead of turning into large square bands.
if (-not (Test-Path -LiteralPath $FontPath -PathType Leaf)) {
    throw "Banner font not found: $FontPath"
}

$fontCollection = New-Object System.Drawing.Text.PrivateFontCollection
$fontCollection.AddFontFile($FontPath)
$fontFamily = $fontCollection.Families[0]

$textHardSource = New-Object System.Drawing.Bitmap(
    $output.Width,
    $output.Height,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)
$textHardGraphics = [System.Drawing.Graphics]::FromImage($textHardSource)
$textHardGraphics.PageUnit = [System.Drawing.GraphicsUnit]::Pixel
$textHardGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
$textHardGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$textHardGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$textHardGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$textHardGraphics.Clear([System.Drawing.Color]::Transparent)

$textFaceMaskSource = New-Object System.Drawing.Bitmap(
    $output.Width,
    $output.Height,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)
$textFaceMaskGraphics = [System.Drawing.Graphics]::FromImage($textFaceMaskSource)
$textFaceMaskGraphics.PageUnit = [System.Drawing.GraphicsUnit]::Pixel
$textFaceMaskGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
$textFaceMaskGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$textFaceMaskGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$textFaceMaskGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$textFaceMaskGraphics.Clear([System.Drawing.Color]::Transparent)

$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$faceBands = @(
    Add-ReferenceText $graphics $textHardGraphics $textFaceMaskGraphics $TitleText $fontFamily 115 81 $output.Width 14 0.98 1.36 -52 47
    Add-ReferenceText $graphics $textHardGraphics $textFaceMaskGraphics $VersionText $fontFamily 45 257 $output.Width 8 1.0 1.25
    Add-ReferenceText $graphics $textHardGraphics $textFaceMaskGraphics $FeatureText $fontFamily 44 311 $output.Width 9 1.0 0.90
    Add-ReferenceText $graphics $textHardGraphics $textFaceMaskGraphics $SupportText $fontFamily 31 381 $output.Width 7 1.0 1.15
)

$textWidth = [int]($output.Width / $TextPixelSize)
$textHeight = [int]($output.Height / $TextPixelSize)
$textHardPixels = New-Object System.Drawing.Bitmap(
    $textWidth,
    $textHeight,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)
$textHardPixelGraphics = [System.Drawing.Graphics]::FromImage($textHardPixels)
$textHardPixelGraphics.PageUnit = [System.Drawing.GraphicsUnit]::Pixel
$textHardPixelGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$textHardPixelGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$textHardPixelGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$textHardPixelGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$textHardPixelGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$textHardPixelGraphics.DrawImage(
    $textHardSource,
    (New-Object System.Drawing.Rectangle(0, 0, $textWidth, $textHeight)),
    0,
    0,
    $textHardSource.Width,
    $textHardSource.Height,
    [System.Drawing.GraphicsUnit]::Pixel
)

$textFaceMaskPixels = New-Object System.Drawing.Bitmap(
    $textWidth,
    $textHeight,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)
$textFacePixelGraphics = [System.Drawing.Graphics]::FromImage($textFaceMaskPixels)
$textFacePixelGraphics.PageUnit = [System.Drawing.GraphicsUnit]::Pixel
$textFacePixelGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$textFacePixelGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$textFacePixelGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$textFacePixelGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$textFacePixelGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$textFacePixelGraphics.DrawImage(
    $textFaceMaskSource,
    (New-Object System.Drawing.Rectangle(0, 0, $textWidth, $textHeight)),
    0,
    0,
    $textFaceMaskSource.Width,
    $textFaceMaskSource.Height,
    [System.Drawing.GraphicsUnit]::Pixel
)

$textFace = New-GradientFaceBitmap `
    $textFaceMaskPixels `
    $output.Width `
    $output.Height `
    $TextPixelSize `
    $faceBands

$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
$graphics.DrawImage(
    $textHardPixels,
    (New-Object System.Drawing.Rectangle(0, 0, $output.Width, $output.Height)),
    0,
    0,
    $textWidth,
    $textHeight,
    [System.Drawing.GraphicsUnit]::Pixel
)
$graphics.DrawImage(
    $textFace,
    (New-Object System.Drawing.Rectangle(0, 0, $output.Width, $output.Height)),
    0,
    0,
    $textFace.Width,
    $textFace.Height,
    [System.Drawing.GraphicsUnit]::Pixel
)

$output.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)

$fontCollection.Dispose()
$textFace.Dispose()
$textFacePixelGraphics.Dispose()
$textFaceMaskPixels.Dispose()
$textHardPixelGraphics.Dispose()
$textHardPixels.Dispose()
$textFaceMaskGraphics.Dispose()
$textFaceMaskSource.Dispose()
$textHardGraphics.Dispose()
$textHardSource.Dispose()
$veil.Dispose()
$sprite.Dispose()
$graphics.Dispose()
$output.Dispose()
$base.Dispose()

Write-Output $OutputPath


