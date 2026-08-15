param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,

    [Parameter(Mandatory = $true)]
    [string]$WindowsIcon,

    [Parameter(Mandatory = $true)]
    [string]$MacIcon,

    [Parameter(Mandatory = $true)]
    [string]$MacMenu16Icon,

    [Parameter(Mandatory = $true)]
    [string]$MacMenu32Icon
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Text;

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

    private static void WriteUInt32BigEndian(BinaryWriter writer, uint value)
    {
        writer.Write(new byte[] {
            (byte)(value >> 24),
            (byte)(value >> 16),
            (byte)(value >> 8),
            (byte)value
        });
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

    private static void WriteIcns(Image source, string outputPath, KeyValuePair<string, int>[] entries)
    {
        var images = new List<byte[]>();
        uint totalSize = 8;
        foreach (var entry in entries)
        {
            byte[] png = RenderPng(source, entry.Value);
            images.Add(png);
            totalSize += (uint)(8 + png.Length);
        }

        using (var stream = File.Create(outputPath))
        using (var writer = new BinaryWriter(stream))
        {
            writer.Write(Encoding.ASCII.GetBytes("icns"));
            WriteUInt32BigEndian(writer, totalSize);

            for (int index = 0; index < entries.Length; ++index)
            {
                writer.Write(Encoding.ASCII.GetBytes(entries[index].Key));
                WriteUInt32BigEndian(writer, (uint)(8 + images[index].Length));
                writer.Write(images[index]);
            }
        }
    }

    public static void Generate(string sourcePath, string icoPath, string icnsPath,
                                string icns16Path, string icns32Path)
    {
        using (Image source = Image.FromFile(sourcePath))
        {
            WriteIco(source, icoPath);
            WriteIcns(source, icnsPath, new[] {
                new KeyValuePair<string, int>("icp4", 16),
                new KeyValuePair<string, int>("icp5", 32),
                new KeyValuePair<string, int>("icp6", 64),
                new KeyValuePair<string, int>("ic07", 128),
                new KeyValuePair<string, int>("ic08", 256),
                new KeyValuePair<string, int>("ic09", 512),
                new KeyValuePair<string, int>("ic10", 1024)
            });
            WriteIcns(source, icns16Path, new[] {
                new KeyValuePair<string, int>("icp4", 16),
                new KeyValuePair<string, int>("icp5", 32)
            });
            WriteIcns(source, icns32Path, new[] {
                new KeyValuePair<string, int>("icp5", 32),
                new KeyValuePair<string, int>("icp6", 64)
            });
        }
    }
}
'@

foreach ($outputPath in @($WindowsIcon, $MacIcon, $MacMenu16Icon, $MacMenu32Icon)) {
    $parent = Split-Path -Parent $outputPath
    if ($parent) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
}

[Chichi77BrandIconGenerator]::Generate(
    (Resolve-Path -LiteralPath $SourcePng).Path,
    [System.IO.Path]::GetFullPath($WindowsIcon),
    [System.IO.Path]::GetFullPath($MacIcon),
    [System.IO.Path]::GetFullPath($MacMenu16Icon),
    [System.IO.Path]::GetFullPath($MacMenu32Icon))
