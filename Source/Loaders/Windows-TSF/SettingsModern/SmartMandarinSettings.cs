using System.Globalization;

namespace KeyKeySettings;

internal static class SmartMandarinSettings
{
    public static int Validate(string keys, string bufferSize)
    {
        if (keys.Length != 0 && (keys.Length != 8 || keys.Any(c => c < '!' || c > '~') || keys.Distinct().Count() != 8))
            throw new ArgumentException("選字按鍵須為 8 個不重複的可輸入 ASCII 按鍵，不可包含空白。");
        if (!int.TryParse(bufferSize, NumberStyles.None, CultureInfo.InvariantCulture, out int size) || size < 10 || size > 20)
            throw new ArgumentException("組字區長度須為 10 至 20 的整數。");
        return size;
    }
}
