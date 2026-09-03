package tw.chichi77.keykey.android;

import android.content.Context;
import android.content.SharedPreferences;

final class CandidateColorSettings {
    enum CandidateColor { PURPLE, GREEN, YELLOW, RED }

    static final String KEY_COLOR = "candidate_highlight_color";

    private CandidateColorSettings() {}

    static CandidateColor color(Context context) {
        return colorFromValue(preferences(context).getString(KEY_COLOR, null));
    }

    static void setColor(Context context, CandidateColor color) {
        preferences(context).edit().putString(KEY_COLOR, valueForColor(color)).apply();
    }

    static CandidateColor colorFromValue(String value) {
        if ("Green".equals(value)) return CandidateColor.GREEN;
        if ("Yellow".equals(value)) return CandidateColor.YELLOW;
        if ("Red".equals(value)) return CandidateColor.RED;
        return CandidateColor.PURPLE;
    }

    static String valueForColor(CandidateColor color) {
        return switch (color) {
            case GREEN -> "Green";
            case YELLOW -> "Yellow";
            case RED -> "Red";
            case PURPLE -> "Purple";
        };
    }

    static int selectionIndex(CandidateColor color) {
        return switch (color) {
            case PURPLE -> 0;
            case GREEN -> 1;
            case YELLOW -> 2;
            case RED -> 3;
        };
    }

    static CandidateColor colorAtSelectionIndex(int index) {
        return switch (index) {
            case 1 -> CandidateColor.GREEN;
            case 2 -> CandidateColor.YELLOW;
            case 3 -> CandidateColor.RED;
            default -> CandidateColor.PURPLE;
        };
    }

    static int backgroundColor(CandidateColor color) {
        return switch (color) {
            case GREEN -> 0xFF3BAD1F;
            case YELLOW -> 0xFFEBB500;
            case RED -> 0xFFBF0029;
            case PURPLE -> 0xFF800080;
        };
    }

    static int textColor(CandidateColor color) {
        return color == CandidateColor.YELLOW ? 0xFF000000 : 0xFFFFFFFF;
    }

    private static SharedPreferences preferences(Context context) {
        return CandidateWindowSettings.preferences(context);
    }
}
