#include <gtk/gtk.h>

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct TestState {
    GtkWidget *window = nullptr;
    GtkWidget *text = nullptr;
    GtkWidget *firstText = nullptr;
    GtkWidget *secondText = nullptr;
    GtkWidget *thirdText = nullptr;
    GMainLoop *loop = nullptr;
    std::string artifactDirectory;
    std::string expectedCommit;
    std::string expectedLiteral;
    std::string expectedFirst;
    std::string expectedSecond;
    std::string expectedThird;
    std::vector<std::string> requiredPreedits;
    std::vector<std::string> requiredEvents;
    std::size_t nextRequiredPreedit = 0;
    std::size_t nextRequiredEvent = 0;
    std::string lastFirstSelectionState;
    bool focusScenario = false;
    bool editingScenario = false;
    bool closeScenario = false;
    bool holdScenario = false;
    bool readyToClose = false;
    bool positiveComplete = false;
    bool clearedAfterPositive = false;
    bool timedOut = false;
    bool success = false;
};

struct TextState {
    TestState *test = nullptr;
    std::string name;
};

std::vector<std::string> split(const std::string &value, char separator) {
    std::vector<std::string> parts;
    std::size_t start = 0;
    while (start <= value.size()) {
        const std::size_t end = value.find(separator, start);
        parts.push_back(value.substr(start, end - start));
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }
    return parts;
}

std::string jsonString(const std::string &value) {
    std::ostringstream output;
    output << '"';
    for (const char rawCharacter : value) {
        const auto character = static_cast<unsigned char>(rawCharacter);
        switch (character) {
        case '"':
            output << "\\\"";
            break;
        case '\\':
            output << "\\\\";
            break;
        case '\b':
            output << "\\b";
            break;
        case '\f':
            output << "\\f";
            break;
        case '\n':
            output << "\\n";
            break;
        case '\r':
            output << "\\r";
            break;
        case '\t':
            output << "\\t";
            break;
        default:
            if (character < 0x20U) {
                output << "\\u" << std::hex << std::setw(4)
                       << std::setfill('0') << static_cast<unsigned>(character)
                       << std::dec;
            } else {
                output << static_cast<char>(character);
            }
        }
    }
    output << '"';
    return output.str();
}

void writeValue(const std::string &path, const std::string &value) {
    std::ofstream output(path, std::ios::trunc | std::ios::binary);
    output << value;
}

void appendEvent(TestState &state, const std::string &type,
                 const std::string &value) {
    std::ofstream output(state.artifactDirectory + "/host-events.log",
                         std::ios::app | std::ios::binary);
    output << type << '=' << value << '\n';

    std::ofstream jsonOutput(state.artifactDirectory + "/events.jsonl",
                             std::ios::app | std::ios::binary);
    jsonOutput << "{\"source\":\"gtk4-host\",\"type\":"
               << jsonString(type) << ",\"value\":" << jsonString(value)
               << "}\n";

    const std::string event = type + "=" + value;
    if (state.nextRequiredEvent < state.requiredEvents.size() &&
        event == state.requiredEvents[state.nextRequiredEvent]) {
        ++state.nextRequiredEvent;
    }
}

std::string textEventType(const TextState &textState,
                          const std::string &event) {
    return textState.name.empty() ? event : textState.name + "-" + event;
}

std::string textValue(GtkWidget *text) {
    return gtk_editable_get_text(GTK_EDITABLE(text));
}

bool sawAllRequiredPreedits(const TestState &state) {
    return state.nextRequiredPreedit == state.requiredPreedits.size();
}

bool sawAllRequiredEvents(const TestState &state) {
    return state.nextRequiredEvent == state.requiredEvents.size();
}

void completeMultiTextScenarioIfReady(TestState &state) {
    if ((!state.focusScenario && !state.editingScenario) || state.success ||
        !sawAllRequiredEvents(state)) {
        return;
    }
    const std::string first = textValue(state.firstText);
    const std::string second = textValue(state.secondText);
    const std::string third = state.thirdText == nullptr
                                  ? std::string{}
                                  : textValue(state.thirdText);
    if (first != state.expectedFirst || second != state.expectedSecond ||
        (state.editingScenario && third != state.expectedThird)) {
        return;
    }
    state.success = true;
    writeValue(state.artifactDirectory + "/final.txt",
               state.editingScenario ? first + "\t" + second + "\t" + third
                                     : first + "\t" + second);
    g_main_loop_quit(state.loop);
}

gboolean completeMultiTextScenarioOnIdle(gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    completeMultiTextScenarioIfReady(state);
    return G_SOURCE_REMOVE;
}

bool writeTextCenter(const TestState &state, GtkWidget *text,
                     const std::string &name) {
    graphene_rect_t bounds{};
    if (!gtk_widget_compute_bounds(text, state.window, &bounds) ||
        bounds.size.width <= 0 || bounds.size.height <= 0) {
        return false;
    }
    const int x = static_cast<int>(
        bounds.origin.x + bounds.size.width / 2.0F);
    const int y = static_cast<int>(
        bounds.origin.y + bounds.size.height / 2.0F);
    writeValue(state.artifactDirectory + "/" + name + "-center.txt",
               std::to_string(x) + " " + std::to_string(y) + "\n");
    return true;
}

bool writeSecondCharacterSelectionPoints(const TestState &state,
                                         GtkWidget *text) {
    const char *value = gtk_editable_get_text(GTK_EDITABLE(text));
    if (g_utf8_strlen(value, -1) < 3) {
        return false;
    }

    const char *selectionStart = g_utf8_offset_to_pointer(value, 1);
    const char *selectionEnd = g_utf8_offset_to_pointer(value, 2);
    PangoLayout *layout = gtk_widget_create_pango_layout(text, value);
    PangoRectangle startPosition{};
    PangoRectangle endPosition{};
    pango_layout_get_cursor_pos(
        layout, static_cast<int>(selectionStart - value), &startPosition,
        nullptr);
    pango_layout_get_cursor_pos(
        layout, static_cast<int>(selectionEnd - value), &endPosition, nullptr);

    graphene_rect_t bounds{};
    if (!gtk_widget_compute_bounds(text, state.window, &bounds)) {
        g_object_unref(layout);
        return false;
    }
    const int characterStart = PANGO_PIXELS(startPosition.x);
    const int characterEnd = PANGO_PIXELS(endPosition.x);
    const int outset = std::max(2, (characterEnd - characterStart) / 6);
    const int y = static_cast<int>(bounds.origin.y + bounds.size.height / 2.0F);
    const int textInset = 8;
    const int startX = static_cast<int>(bounds.origin.x) + textInset +
                       characterStart - outset;
    const int endX = static_cast<int>(bounds.origin.x) + textInset +
                     characterEnd - outset;
    writeValue(state.artifactDirectory + "/first-selection-start.txt",
               std::to_string(startX) + " " + std::to_string(y) + "\n");
    writeValue(state.artifactDirectory + "/first-selection-end.txt",
               std::to_string(endX) + " " + std::to_string(y) + "\n");
    g_object_unref(layout);
    return true;
}

gboolean writeTextCentersOnIdle(gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    if (!writeTextCenter(state, state.firstText, "first") ||
        !writeTextCenter(state, state.secondText, "second") ||
        (state.editingScenario &&
         (!writeTextCenter(state, state.thirdText, "third") ||
          !writeSecondCharacterSelectionPoints(state, state.firstText)))) {
        return G_SOURCE_CONTINUE;
    }
    return G_SOURCE_REMOVE;
}

void onPreeditChanged(GtkText *, gchar *preedit, gpointer userData) {
    auto &textState = *static_cast<TextState *>(userData);
    auto &state = *textState.test;
    const std::string value = preedit == nullptr ? "" : preedit;
    appendEvent(state, textEventType(textState, "preedit"), value);
    if (state.focusScenario || state.editingScenario) {
        completeMultiTextScenarioIfReady(state);
        return;
    }
    if (state.nextRequiredPreedit < state.requiredPreedits.size() &&
        value == state.requiredPreedits[state.nextRequiredPreedit]) {
        ++state.nextRequiredPreedit;
    }
    if (state.closeScenario && !state.readyToClose &&
        sawAllRequiredPreedits(state)) {
        state.readyToClose = true;
        writeValue(state.artifactDirectory + "/ready-to-close", value);
    }
}

void onTextChanged(GtkEditable *editable, gpointer userData) {
    auto &textState = *static_cast<TextState *>(userData);
    auto &state = *textState.test;
    const std::string value = gtk_editable_get_text(editable);
    appendEvent(state, textEventType(textState, "text"), value);

    if (state.focusScenario || state.editingScenario) {
        completeMultiTextScenarioIfReady(state);
        return;
    }
    if (state.closeScenario || state.holdScenario) {
        return;
    }
    if (!state.positiveComplete && value == state.expectedCommit &&
        sawAllRequiredPreedits(state)) {
        state.positiveComplete = true;
        writeValue(state.artifactDirectory + "/positive-ready", value);
        return;
    }
    if (state.positiveComplete && value.empty()) {
        state.clearedAfterPositive = true;
        return;
    }
    if (state.clearedAfterPositive && value == state.expectedLiteral) {
        state.success = true;
        writeValue(state.artifactDirectory + "/final.txt", value);
        g_main_loop_quit(state.loop);
    }
}

void onFocusChanged(GObject *object, GParamSpec *, gpointer userData) {
    auto &textState = *static_cast<TextState *>(userData);
    auto &state = *textState.test;
    appendEvent(state, textEventType(textState, "focus"),
                gtk_widget_has_focus(GTK_WIDGET(object)) ? "in" : "out");
    completeMultiTextScenarioIfReady(state);
}

void observeFirstSelection(GtkEditable *editable, TextState &textState) {
    auto &state = *textState.test;
    int start = 0;
    int end = 0;
    const bool hasSelection =
        gtk_editable_get_selection_bounds(editable, &start, &end);
    if (start > end) {
        std::swap(start, end);
    }
    const std::string value =
        hasSelection ? std::to_string(start) + ":" + std::to_string(end)
                     : "cursor:" +
                           std::to_string(gtk_editable_get_position(editable));
    if (value == state.lastFirstSelectionState) {
        return;
    }
    state.lastFirstSelectionState = value;
    writeValue(state.artifactDirectory + "/first-selection-state.txt",
               value + "\n");
    if (hasSelection) {
        appendEvent(state, textEventType(textState, "selection"), value);
        completeMultiTextScenarioIfReady(state);
    }
}

void onSelectionChanged(GObject *editable, GParamSpec *, gpointer userData) {
    auto &textState = *static_cast<TextState *>(userData);
    observeFirstSelection(GTK_EDITABLE(editable), textState);
}

gboolean pollFirstSelection(gpointer userData) {
    auto &textState = *static_cast<TextState *>(userData);
    observeFirstSelection(GTK_EDITABLE(textState.test->firstText), textState);
    return G_SOURCE_CONTINUE;
}

gboolean onKeyPressed(GtkEventControllerKey *, guint keyval, guint,
                      GdkModifierType, gpointer userData) {
    auto &textState = *static_cast<TextState *>(userData);
    auto &state = *textState.test;
    const char *name = gdk_keyval_name(keyval);
    appendEvent(state, textEventType(textState, "key-press"),
                name == nullptr ? "" : name);
    if (state.editingScenario) {
        g_idle_add(completeMultiTextScenarioOnIdle, &state);
    }
    return FALSE;
}

gboolean onTimeout(gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    if (state.focusScenario || state.editingScenario) {
        const std::string first = textValue(state.firstText);
        const std::string second = textValue(state.secondText);
        appendEvent(state, "timeout-first-text", first);
        appendEvent(state, "timeout-second-text", second);
        if (state.editingScenario) {
            const std::string third = textValue(state.thirdText);
            appendEvent(state, "timeout-third-text", third);
            writeValue(state.artifactDirectory + "/final.txt",
                       first + "\t" + second + "\t" + third);
        } else {
            writeValue(state.artifactDirectory + "/final.txt",
                       first + "\t" + second);
        }
    } else {
        const std::string value = textValue(state.text);
        appendEvent(state, "timeout-text", value);
        writeValue(state.artifactDirectory + "/final.txt", value);
    }
    state.timedOut = true;
    g_main_loop_quit(state.loop);
    return G_SOURCE_REMOVE;
}

gboolean onControlFile(gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    std::ifstream input(state.artifactDirectory + "/close-now",
                        std::ios::binary);
    if (!input.good()) {
        return G_SOURCE_CONTINUE;
    }
    appendEvent(state, "close-command", "received");
    if (state.holdScenario) {
        state.success = true;
        writeValue(state.artifactDirectory + "/final.txt",
                   textValue(state.text));
    } else if (state.closeScenario && state.readyToClose) {
        state.success = true;
        writeValue(state.artifactDirectory + "/final.txt", "closed");
    }
    gtk_window_destroy(GTK_WINDOW(state.window));
    state.window = nullptr;
    g_main_loop_quit(state.loop);
    return G_SOURCE_REMOVE;
}

} // namespace

int main() {
    if (!gtk_init_check()) {
        return EXIT_FAILURE;
    }

    const char *artifactDirectory = std::getenv("KEYKEY_E2E_CASE_DIR");
    const char *expectedCommit = std::getenv("KEYKEY_E2E_EXPECTED_COMMIT");
    const char *expectedLiteral = std::getenv("KEYKEY_E2E_EXPECTED_LITERAL");
    const char *requiredPreedits =
        std::getenv("KEYKEY_E2E_REQUIRED_PREEDITS");
    const char *scenario = std::getenv("KEYKEY_E2E_SCENARIO");
    const bool focusScenario =
        scenario != nullptr && std::string(scenario) == "focus";
    const bool editingScenario =
        scenario != nullptr && std::string(scenario) == "editing";
    const bool closeScenario =
        scenario != nullptr && std::string(scenario) == "close";
    const bool holdScenario =
        scenario != nullptr && std::string(scenario) == "hold";
    const char *windowTitle = std::getenv("KEYKEY_E2E_WINDOW_TITLE");
    const char *expectedFirst = std::getenv("KEYKEY_E2E_EXPECTED_FIRST");
    const char *expectedSecond = std::getenv("KEYKEY_E2E_EXPECTED_SECOND");
    const char *expectedThird = std::getenv("KEYKEY_E2E_EXPECTED_THIRD");
    const char *requiredEvents = std::getenv("KEYKEY_E2E_REQUIRED_EVENTS");
    if (artifactDirectory == nullptr || *artifactDirectory == '\0' ||
        (!focusScenario && !editingScenario && !closeScenario &&
         !holdScenario &&
         (expectedCommit == nullptr || *expectedCommit == '\0' ||
          expectedLiteral == nullptr || requiredPreedits == nullptr)) ||
        (closeScenario && requiredPreedits == nullptr) ||
        ((focusScenario || editingScenario) &&
         (expectedFirst == nullptr || expectedSecond == nullptr ||
          requiredEvents == nullptr)) ||
        (editingScenario && expectedThird == nullptr)) {
        return EXIT_FAILURE;
    }

    TestState state;
    state.artifactDirectory = artifactDirectory;
    state.focusScenario = focusScenario;
    state.editingScenario = editingScenario;
    state.closeScenario = closeScenario;
    state.holdScenario = holdScenario;
    if (focusScenario || editingScenario) {
        state.expectedFirst = expectedFirst;
        state.expectedSecond = expectedSecond;
        if (editingScenario) {
            state.expectedThird = expectedThird;
        }
        if (*requiredEvents != '\0') {
            state.requiredEvents = split(requiredEvents, ';');
        }
    } else if (!closeScenario && !holdScenario) {
        state.expectedCommit = expectedCommit;
        state.expectedLiteral = expectedLiteral;
    }
    if (!focusScenario && !editingScenario && requiredPreedits != nullptr &&
        *requiredPreedits != '\0') {
        state.requiredPreedits = split(requiredPreedits, ',');
    }
    state.loop = g_main_loop_new(nullptr, FALSE);

    GtkWidget *window = gtk_window_new();
    state.window = window;
    gtk_window_set_title(
        GTK_WINDOW(window),
        windowTitle == nullptr || *windowTitle == '\0'
            ? "chichi77-keykey-gtk4-e2e"
            : windowTitle);
    gtk_window_set_default_size(GTK_WINDOW(window),
                                focusScenario ? 960 : 480,
                                editingScenario ? 160 : 100);

    TextState firstTextState{
        &state, focusScenario || editingScenario ? "first" : ""};
    TextState secondTextState{&state, "second"};
    TextState thirdTextState{&state, "third"};
    state.text = gtk_text_new();
    state.firstText = state.text;
    gtk_text_set_placeholder_text(
        GTK_TEXT(state.firstText),
        "Keyboard input must arrive through the IME");
    g_signal_connect(state.firstText, "preedit-changed",
                     G_CALLBACK(onPreeditChanged), &firstTextState);
    g_signal_connect(state.firstText, "changed", G_CALLBACK(onTextChanged),
                     &firstTextState);
    if (focusScenario || editingScenario || holdScenario) {
        g_signal_connect(state.firstText, "notify::has-focus",
                         G_CALLBACK(onFocusChanged), &firstTextState);
    }

    if (focusScenario || editingScenario) {
        GtkWidget *box = gtk_box_new(
            focusScenario ? GTK_ORIENTATION_HORIZONTAL
                          : GTK_ORIENTATION_VERTICAL,
            8);
        state.secondText = gtk_text_new();
        gtk_text_set_placeholder_text(
            GTK_TEXT(state.secondText),
            editingScenario ? "Password input context"
                            : "Second independent input context");
        g_signal_connect(state.secondText, "preedit-changed",
                         G_CALLBACK(onPreeditChanged), &secondTextState);
        g_signal_connect(state.secondText, "changed",
                         G_CALLBACK(onTextChanged), &secondTextState);
        g_signal_connect(state.secondText, "notify::has-focus",
                         G_CALLBACK(onFocusChanged), &secondTextState);
        gtk_box_append(GTK_BOX(box), state.firstText);
        gtk_box_append(GTK_BOX(box), state.secondText);
        if (editingScenario) {
            gtk_editable_set_text(GTK_EDITABLE(state.firstText), "甲乙丙");
            g_signal_connect(state.firstText, "notify::selection-bound",
                             G_CALLBACK(onSelectionChanged), &firstTextState);
            g_timeout_add(20, pollFirstSelection, &firstTextState);
            gtk_text_set_visibility(GTK_TEXT(state.secondText), FALSE);
            gtk_text_set_input_purpose(GTK_TEXT(state.secondText),
                                       GTK_INPUT_PURPOSE_PASSWORD);

            state.thirdText = gtk_text_new();
            gtk_editable_set_text(GTK_EDITABLE(state.thirdText), "唯讀");
            gtk_editable_set_editable(GTK_EDITABLE(state.thirdText), FALSE);
            gtk_text_set_placeholder_text(GTK_TEXT(state.thirdText),
                                          "Read-only input context");
            g_signal_connect(state.thirdText, "preedit-changed",
                             G_CALLBACK(onPreeditChanged), &thirdTextState);
            g_signal_connect(state.thirdText, "changed",
                             G_CALLBACK(onTextChanged), &thirdTextState);
            g_signal_connect(state.thirdText, "notify::has-focus",
                             G_CALLBACK(onFocusChanged), &thirdTextState);
            GtkEventController *keyController =
                gtk_event_controller_key_new();
            g_signal_connect(keyController, "key-pressed",
                             G_CALLBACK(onKeyPressed), &thirdTextState);
            gtk_widget_add_controller(state.thirdText, keyController);
            gtk_box_append(GTK_BOX(box), state.thirdText);
        }
        gtk_window_set_child(GTK_WINDOW(window), box);
    } else {
        gtk_window_set_child(GTK_WINDOW(window), state.firstText);
    }

    gtk_window_present(GTK_WINDOW(window));
    gtk_widget_grab_focus(state.firstText);
    if (focusScenario || editingScenario) {
        g_idle_add(writeTextCentersOnIdle, &state);
    }
    if (closeScenario || holdScenario) {
        g_timeout_add(20, onControlFile, &state);
    }
    const guint timeoutSource = g_timeout_add_seconds(20, onTimeout, &state);
    g_main_loop_run(state.loop);
    if (!state.timedOut) {
        g_source_remove(timeoutSource);
    }
    appendEvent(state, "result", state.success ? "passed" : "failed");
    if (state.window != nullptr) {
        gtk_window_destroy(GTK_WINDOW(state.window));
    }
    g_main_loop_unref(state.loop);
    return state.success ? EXIT_SUCCESS : EXIT_FAILURE;
}
