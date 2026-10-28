param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,

    [Parameter(Mandatory = $true)]
    [string]$WindowsIcon,

    [string]$MacIcon,

    [string]$MacMenu16Icon,

    [string]$MacMenu32Icon
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# macOS icons need Apple's iconutil for compatible small/Retina representations.
# Keep legacy arguments only to give callers an actionable migration error.
if ($MacIcon -or $MacMenu16Icon -or $MacMenu32Icon) {
    throw 'Generate macOS ICNS with bash Source/Utilities/generate-macos-icons.sh on macOS; this tool generates Windows ICO only.'
}

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class Chichi77BrandIconGenerator
{
    private static byte[] RenderPng(Image source, int size)
    {
        using (var bitmap = new Bitmap(size, size, PixelFormat.Format32bppArgb))
        {
            bitmap.SetResolution(72, 72);
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                graphics.Clear(Color.White);
                graphics.CompositingMode = CompositingMode.SourceOver;
                graphics.CompositingQuality = CompositingQuality.HighQuality;
                graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                graphics.SmoothingMode = SmoothingMode.HighQuality;
                graphics.DrawImage(source, new Rectangle(0, 0, size, size));
            }

            // The generated artwork is already white, but normalizing its
            // near-white background keeps the tiny taskbar icons truly white.
            for (int y = 0; y < size; ++y)
            {
                for (int x = 0; x < size; ++x)
                {
                    Color color = bitmap.GetPixel(x, y);
                    if (color.R >= 240 && color.G >= 240 && color.B >= 240)
                    {
                        bitmap.SetPixel(x, y, Color.White);
                    }
                }
            }

            using (var stream = new MemoryStream())
            {
                bitmap.Save(stream, ImageFormat.Png);
                return stream.ToArray();
            }
        }
    }

    private static void WriteIco(Image source, string outputPath)
    {
        int[] sizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };
        var images = new List<byte[]>();
        foreach (int size in sizes)
        {
            images.Add(RenderPng(source, size));
        }

        using (var stream = File.Create(outputPath))
        using (var writer = new BinaryWriter(stream))
        {
            writer.Write((ushort)0);
            writer.Write((ushort)1);
            writer.Write((ushort)sizes.Length);

            uint offset = (uint)(6 + 16 * sizes.Length);
            for (int index = 0; index < sizes.Length; ++index)
            {
                int size = sizes[index];
                byte encodedSize = size == 256 ? (byte)0 : (byte)size;
                writer.Write(encodedSize);
                writer.Write(encodedSize);
                writer.Write((byte)0);
                writer.Write((byte)0);
                writer.Write((ushort)1);
                writer.Write((ushort)32);
                writer.Write((uint)images[index].Length);
                writer.Write(offset);
                offset += (uint)images[index].Length;
            }

            foreach (byte[] image in images)
            {
                writer.Write(image);
            }
        }
    }

    public static void Generate(string sourcePath, string icoPath)
    {
        using (Image source = Image.FromFile(sourcePath))
        {
            WriteIco(source, icoPath);
        }
    }
}
'@

foreach ($outputPath in @($WindowsIcon)) {
    $parent = Split-Path -Parent $outputPath
    if ($parent) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
}

[Chichi77BrandIconGenerator]::Generate(
    (Resolve-Path -LiteralPath $SourcePng).Path,
    [System.IO.Path]::GetFullPath($WindowsIcon))
