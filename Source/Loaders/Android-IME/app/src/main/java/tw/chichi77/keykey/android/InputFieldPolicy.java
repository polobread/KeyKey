package tw.chichi77.keykey.android;

import android.text.InputType;
import android.view.inputmethod.EditorInfo;

import java.util.EnumSet;
import java.util.Set;

/** Converts host field hints into a keyboard layout and tappable-key policy. */
final class InputFieldPolicy {
    enum Kind { GENERAL, ASCII, EMAIL, URL, PHONE, INTEGER, DECIMAL, DATE_TIME }

    static final InputFieldPolicy DEFAULT = new InputFieldPolicy(
            Kind.GENERAL, EnumSet.allOf(BopomofoEngine.InputMode.class),
            BopomofoEngine.InputMode.BOPOMOFO, EditorInfo.IME_ACTION_NONE, "", false);

    private final Kind kind;
    private final EnumSet<BopomofoEngine.InputMode> allowedModes;
    private final BopomofoEngine.InputMode preferredMode;
    private final int editorAction;
    private final String enterLabel;
    private final boolean hasEditorAction;
    private final boolean signedNumber;

    private InputFieldPolicy(Kind kind, EnumSet<BopomofoEngine.InputMode> allowedModes,
                             BopomofoEngine.InputMode preferredMode, int editorAction,
                             String enterLabel, boolean hasEditorAction) {
        this(kind, allowedModes, preferredMode, editorAction, enterLabel,
                hasEditorAction, false);
    }

    private InputFieldPolicy(Kind kind, EnumSet<BopomofoEngine.InputMode> allowedModes,
                             BopomofoEngine.InputMode preferredMode, int editorAction,
                             String enterLabel, boolean hasEditorAction,
                             boolean signedNumber) {
        this.kind = kind;
        this.allowedModes = allowedModes;
        this.preferredMode = preferredMode;
        this.editorAction = editorAction;
        this.enterLabel = enterLabel;
        this.hasEditorAction = hasEditorAction;
        this.signedNumber = signedNumber;
    }

    static InputFieldPolicy from(EditorInfo info) {
        if (info == null) return DEFAULT;
        return fromValues(info.inputType, info.imeOptions,
                info.actionLabel == null ? "" : info.actionLabel.toString(), info.actionId);
    }

    static InputFieldPolicy fromValues(int type, int imeOptions) {
        return fromValues(type, imeOptions, "", EditorInfo.IME_ACTION_NONE);
    }

    static InputFieldPolicy fromValues(int type, int imeOptions, String customActionLabel,
                                       int customActionId) {
        int inputClass = type & InputType.TYPE_MASK_CLASS;
        int variation = type & InputType.TYPE_MASK_VARIATION;
        Kind kind;
        if (inputClass == InputType.TYPE_CLASS_NUMBER) {
            kind = (type & InputType.TYPE_NUMBER_FLAG_DECIMAL) != 0
                    ? Kind.DECIMAL : Kind.INTEGER;
        } else if (inputClass == InputType.TYPE_CLASS_PHONE) {
            kind = Kind.PHONE;
        } else if (inputClass == InputType.TYPE_CLASS_DATETIME) {
            kind = Kind.DATE_TIME;
        } else if (inputClass == InputType.TYPE_CLASS_TEXT) {
            kind = switch (variation) {
                case InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                        InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS -> Kind.EMAIL;
                case InputType.TYPE_TEXT_VARIATION_URI -> Kind.URL;
                case InputType.TYPE_TEXT_VARIATION_PASSWORD,
                        InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                        InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD -> Kind.ASCII;
                default -> Kind.GENERAL;
            };
        } else {
            kind = Kind.GENERAL;
        }

        EnumSet<BopomofoEngine.InputMode> modes;
        BopomofoEngine.InputMode preferred;
        if (kind == Kind.PHONE || kind == Kind.INTEGER || kind == Kind.DECIMAL
                || kind == Kind.DATE_TIME) {
            modes = EnumSet.of(BopomofoEngine.InputMode.NUMBER);
            preferred = BopomofoEngine.InputMode.NUMBER;
        } else if (kind == Kind.ASCII || kind == Kind.EMAIL || kind == Kind.URL) {
            modes = EnumSet.of(BopomofoEngine.InputMode.ENGLISH,
                    BopomofoEngine.InputMode.NUMBER);
            preferred = BopomofoEngine.InputMode.ENGLISH;
        } else {
            modes = EnumSet.allOf(BopomofoEngine.InputMode.class);
            preferred = BopomofoEngine.InputMode.BOPOMOFO;
        }

        int action = resolveAction(imeOptions);
        boolean enterActionAllowed = (imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) == 0;
        String normalizedCustomLabel = customActionLabel == null ? ""
                : customActionLabel.replace('\n', ' ').replace('\r', ' ').trim();
        boolean hasCustomAction = enterActionAllowed && !normalizedCustomLabel.isEmpty();
        boolean hasStandardAction = action != EditorInfo.IME_ACTION_NONE;
        if (hasCustomAction) action = customActionId;
        boolean signed = inputClass == InputType.TYPE_CLASS_NUMBER
                && (type & InputType.TYPE_NUMBER_FLAG_SIGNED) != 0;
        return new InputFieldPolicy(kind, modes, preferred, action,
                hasCustomAction ? normalizedCustomLabel : actionLabel(action),
                hasCustomAction || hasStandardAction, signed);
    }

    private static int resolveAction(int imeOptions) {
        if ((imeOptions & EditorInfo.IME_FLAG_NO_ENTER_ACTION) != 0) {
            return EditorInfo.IME_ACTION_NONE;
        }
        int action = imeOptions & EditorInfo.IME_MASK_ACTION;
        return switch (action) {
            case EditorInfo.IME_ACTION_DONE, EditorInfo.IME_ACTION_NEXT,
                    EditorInfo.IME_ACTION_SEARCH, EditorInfo.IME_ACTION_SEND,
                    EditorInfo.IME_ACTION_GO, EditorInfo.IME_ACTION_PREVIOUS -> action;
            default -> EditorInfo.IME_ACTION_NONE;
        };
    }

    private static String actionLabel(int action) {
        return switch (action) {
            case EditorInfo.IME_ACTION_DONE -> "完成";
            case EditorInfo.IME_ACTION_NEXT -> "下一個";
            case EditorInfo.IME_ACTION_SEARCH -> "搜尋";
            case EditorInfo.IME_ACTION_SEND -> "傳送";
            case EditorInfo.IME_ACTION_GO -> "前往";
            case EditorInfo.IME_ACTION_PREVIOUS -> "上一個";
            default -> "";
        };
    }

    Set<BopomofoEngine.InputMode> allowedModes() { return EnumSet.copyOf(allowedModes); }
    BopomofoEngine.InputMode preferredMode() { return preferredMode; }
    int editorAction() { return editorAction; }
    String enterLabel() { return enterLabel; }
    boolean hasEditorAction() { return hasEditorAction; }
    Kind kind() { return kind; }

    boolean hasSameLayout(InputFieldPolicy other) {
        return other != null && kind == other.kind
                && allowedModes.equals(other.allowedModes)
                && signedNumber == other.signedNumber;
    }

    String modeCaption(BopomofoEngine.InputMode mode) {
        if (allowedModes.size() == 1) return symbol(mode);
        if (allowedModes.size() == 2) return symbol(nextMode(mode));
        return switch (mode) {
            case BOPOMOFO -> "英/數";
            case ENGLISH -> "數/ㄅ";
            case NUMBER -> "ㄅ/英";
        };
    }

    boolean isKeyEnabled(String key, BopomofoEngine.InputMode mode, boolean shifted) {
        if (key.equals("SETTINGS") || key.equals("BACKSPACE") || key.equals("ENTER")) {
            return true;
        }
        if (key.equals("MODE")) return allowedModes.size() > 1;
        if (key.equals("SYMBOL") || key.equals("EMOJI")
                || key.equals("，") || key.equals("。")) {
            return kind == Kind.GENERAL;
        }
        if (key.equals("SPACE")) return allowsCharacter(" ");
        if (key.equals("SHIFT")) {
            if (mode == BopomofoEngine.InputMode.BOPOMOFO) {
                return allowedModes.contains(BopomofoEngine.InputMode.ENGLISH);
            }
            String[][] shiftedRows = mode == BopomofoEngine.InputMode.ENGLISH
                    ? BopomofoKeyboardView.shiftedEnglishRows()
                    : BopomofoKeyboardView.shiftedNumberRows();
            for (String[] row : shiftedRows) {
                for (String candidate : row) {
                    if (candidate.length() == 1 && allowsCharacter(candidate)) return true;
                }
            }
            return false;
        }
        if (!allowedModes.contains(mode)) return false;
        if (mode == BopomofoEngine.InputMode.BOPOMOFO) return true;
        return key.length() == 1 && allowsCharacter(key);
    }

    private boolean allowsCharacter(String value) {
        if (value.length() != 1) return false;
        char character = value.charAt(0);
        return switch (kind) {
            case GENERAL -> true;
            case ASCII -> character >= 0x20 && character <= 0x7E;
            case EMAIL -> character >= 0x21 && character <= 0x7E;
            case URL -> character >= 0x21 && character <= 0x7E;
            case PHONE -> Character.isDigit(character)
                    || "+-#*() ".indexOf(character) >= 0;
            case INTEGER -> Character.isDigit(character)
                    || signedNumber && character == '-';
            case DECIMAL -> Character.isDigit(character) || character == '.'
                    || signedNumber && character == '-';
            case DATE_TIME -> Character.isDigit(character) || "/:-. ".indexOf(character) >= 0;
        };
    }

    private BopomofoEngine.InputMode nextMode(BopomofoEngine.InputMode current) {
        BopomofoEngine.InputMode candidate = current;
        do {
            candidate = switch (candidate) {
                case BOPOMOFO -> BopomofoEngine.InputMode.ENGLISH;
                case ENGLISH -> BopomofoEngine.InputMode.NUMBER;
                case NUMBER -> BopomofoEngine.InputMode.BOPOMOFO;
            };
        } while (!allowedModes.contains(candidate));
        return candidate;
    }

    private static String symbol(BopomofoEngine.InputMode mode) {
        return switch (mode) {
            case BOPOMOFO -> "ㄅ";
            case ENGLISH -> "英";
            case NUMBER -> "數";
        };
    }
}
