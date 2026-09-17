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
    GtkWidget *entry = nullptr;
    GtkWidget *firstEntry = nullptr;
    GtkWidget *secondEntry = nullptr;
    GtkWidget *thirdEntry = nullptr;
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
    bool success = false;
};

struct EntryState {
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

bool sawAllRequiredPreedits(const TestState &state) {
    return state.nextRequiredPreedit == state.requiredPreedits.size();
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

void appendEvent(TestState &state, const std::string &type,
                 const std::string &value) {
    std::ofstream output(state.artifactDirectory + "/host-events.log",
                         std::ios::app | std::ios::binary);
    output << type << '=' << value << '\n';

    std::ofstream jsonOutput(state.artifactDirectory + "/events.jsonl",
                             std::ios::app | std::ios::binary);
    jsonOutput << "{\"source\":\"gtk3-host\",\"type\":"
               << jsonString(type) << ",\"value\":" << jsonString(value)
               << "}\n";

    const std::string event = type + "=" + value;
    if (state.nextRequiredEvent < state.requiredEvents.size() &&
        event == state.requiredEvents[state.nextRequiredEvent]) {
        ++state.nextRequiredEvent;
    }
}

void writeValue(const std::string &path, const std::string &value) {
    std::ofstream output(path, std::ios::trunc | std::ios::binary);
    output << value;
}

bool writeEntryCenter(const TestState &state, GtkWidget *entry,
                      const std::string &name) {
    GtkAllocation allocation;
    gtk_widget_get_allocation(entry, &allocation);
    gint x = 0;
    gint y = 0;
    if (!gtk_widget_translate_coordinates(
            entry, state.window, allocation.width / 2, allocation.height / 2,
            &x, &y)) {
        return false;
    }
    writeValue(state.artifactDirectory + "/" + name + "-center.txt",
               std::to_string(x) + " " + std::to_string(y) + "\n");
    return true;
}

bool writeSecondCharacterSelectionPoints(const TestState &state,
                                         GtkWidget *entry) {
    const gchar *text = gtk_entry_get_text(GTK_ENTRY(entry));
    if (g_utf8_strlen(text, -1) < 3) {
        return false;
    }

    const gchar *selectionStart = g_utf8_offset_to_pointer(text, 1);
    const gchar *selectionEnd = g_utf8_offset_to_pointer(text, 2);
    PangoLayout *layout = gtk_entry_get_layout(GTK_ENTRY(entry));
    PangoRectangle startPosition{};
    PangoRectangle endPosition{};
    pango_layout_get_cursor_pos(
        layout, static_cast<int>(selectionStart - text), &startPosition,
        nullptr);
    pango_layout_get_cursor_pos(
        layout, static_cast<int>(selectionEnd - text), &endPosition, nullptr);

    gint layoutX = 0;
    gint layoutY = 0;
    gtk_entry_get_layout_offsets(GTK_ENTRY(entry), &layoutX, &layoutY);
    GtkAllocation allocation;
    gtk_widget_get_allocation(entry, &allocation);
    gint startX = 0;
    gint startY = 0;
    gint endX = 0;
    gint endY = 0;
    const gint y = allocation.height / 2;
    const gint characterStart = PANGO_PIXELS(startPosition.x);
    const gint characterEnd = PANGO_PIXELS(endPosition.x);
    const gint outset = std::max(2, (characterEnd - characterStart) / 6);
    if (!gtk_widget_translate_coordinates(
            entry, state.window, layoutX + characterStart - outset, y, &startX,
            &startY) ||
        !gtk_widget_translate_coordinates(
            entry, state.window, layoutX + characterEnd + outset, y, &endX,
            &endY)) {
        return false;
    }
    writeValue(state.artifactDirectory + "/first-selection-start.txt",
               std::to_string(startX) + " " + std::to_string(startY) + "\n");
    writeValue(state.artifactDirectory + "/first-selection-end.txt",
               std::to_string(endX) + " " + std::to_string(endY) + "\n");
    return true;
}

gboolean writeEntryCentersOnIdle(gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    if (!writeEntryCenter(state, state.firstEntry, "first") ||
        !writeEntryCenter(state, state.secondEntry, "second") ||
        (state.editingScenario &&
         (!writeEntryCenter(state, state.thirdEntry, "third") ||
          !writeSecondCharacterSelectionPoints(state, state.firstEntry)))) {
        return G_SOURCE_CONTINUE;
    }
    return G_SOURCE_REMOVE;
}

std::string entryEventType(const EntryState &entryState,
                           const std::string &event) {
    return entryState.name.empty() ? event : entryState.name + "-" + event;
}

bool sawAllRequiredEvents(const TestState &state) {
    return state.nextRequiredEvent == state.requiredEvents.size();
}

void completeMultiEntryScenarioIfReady(TestState &state) {
    if ((!state.focusScenario && !state.editingScenario) || state.success ||
        !sawAllRequiredEvents(state)) {
        return;
    }
    const std::string first =
        gtk_entry_get_text(GTK_ENTRY(state.firstEntry));
    const std::string second =
        gtk_entry_get_text(GTK_ENTRY(state.secondEntry));
    const std::string third = state.thirdEntry == nullptr
                                  ? std::string{}
                                  : gtk_entry_get_text(
                                        GTK_ENTRY(state.thirdEntry));
    if (first != state.expectedFirst || second != state.expectedSecond ||
        (state.editingScenario && third != state.expectedThird)) {
        return;
    }
    state.success = true;
    writeValue(state.artifactDirectory + "/final.txt",
               state.editingScenario ? first + "\t" + second + "\t" + third
                                     : first + "\t" + second);
    gtk_main_quit();
}

gboolean completeMultiEntryScenarioOnIdle(gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    completeMultiEntryScenarioIfReady(state);
    return G_SOURCE_REMOVE;
}

void onPreeditChanged(GtkEntry *, gchar *preedit, gpointer userData) {
    auto &entryState = *static_cast<EntryState *>(userData);
    auto &state = *entryState.test;
    const std::string value = preedit == nullptr ? "" : preedit;
    appendEvent(state, entryEventType(entryState, "preedit"), value);
    if (state.focusScenario || state.editingScenario) {
        completeMultiEntryScenarioIfReady(state);
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
    auto &entryState = *static_cast<EntryState *>(userData);
    auto &state = *entryState.test;
    const std::string value = gtk_entry_get_text(GTK_ENTRY(editable));
    appendEvent(state, entryEventType(entryState, "text"), value);

    if (state.focusScenario || state.editingScenario) {
        completeMultiEntryScenarioIfReady(state);
        return;
    }
    if (state.closeScenario) {
        return;
    }
    if (state.holdScenario) {
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
        gtk_main_quit();
    }
}

void observeFirstSelection(GtkEditable *editable, EntryState &entryState) {
    auto &state = *entryState.test;
    gint start = 0;
    gint end = 0;
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
        appendEvent(state, entryEventType(entryState, "selection"), value);
        completeMultiEntryScenarioIfReady(state);
    }
}

void onSelectionChanged(GObject *editable, GParamSpec *, gpointer userData) {
    auto &entryState = *static_cast<EntryState *>(userData);
    observeFirstSelection(GTK_EDITABLE(editable), entryState);
}

gboolean pollFirstSelection(gpointer userData) {
    auto &entryState = *static_cast<EntryState *>(userData);
    observeFirstSelection(GTK_EDITABLE(entryState.test->firstEntry), entryState);
    return G_SOURCE_CONTINUE;
}

gboolean onFocusEvent(GtkWidget *, GdkEventFocus *event, gpointer userData) {
    auto &entryState = *static_cast<EntryState *>(userData);
    auto &state = *entryState.test;
    appendEvent(state, entryEventType(entryState, "focus"),
                event->in ? "in" : "out");
    return FALSE;
}

gboolean onKeyPress(GtkWidget *, GdkEventKey *event, gpointer userData) {
    auto &entryState = *static_cast<EntryState *>(userData);
    auto &state = *entryState.test;
    const gchar *name = gdk_keyval_name(event->keyval);
    appendEvent(state, entryEventType(entryState, "key-press"),
                name == nullptr ? "" : name);
    if (state.editingScenario) {
        g_idle_add(completeMultiEntryScenarioOnIdle, &state);
    }
    return FALSE;
}

gboolean onTimeout(gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    if (state.focusScenario || state.editingScenario) {
        const std::string first =
            gtk_entry_get_text(GTK_ENTRY(state.firstEntry));
        const std::string second =
            gtk_entry_get_text(GTK_ENTRY(state.secondEntry));
        appendEvent(state, "timeout-first-text", first);
        appendEvent(state, "timeout-second-text", second);
        if (state.editingScenario) {
            const std::string third =
                gtk_entry_get_text(GTK_ENTRY(state.thirdEntry));
            appendEvent(state, "timeout-third-text", third);
            writeValue(state.artifactDirectory + "/final.txt",
                       first + "\t" + second + "\t" + third);
        } else {
            writeValue(state.artifactDirectory + "/final.txt",
                       first + "\t" + second);
        }
        gtk_main_quit();
        return G_SOURCE_REMOVE;
    }
    const std::string value = gtk_entry_get_text(GTK_ENTRY(state.entry));
    appendEvent(state, "timeout-text", value);
    writeValue(state.artifactDirectory + "/final.txt", value);
    gtk_main_quit();
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
    gtk_widget_destroy(state.window);
    return G_SOURCE_REMOVE;
}

void onDestroy(GtkWidget *, gpointer userData) {
    auto &state = *static_cast<TestState *>(userData);
    if (state.holdScenario) {
        state.success = true;
        writeValue(state.artifactDirectory + "/final.txt",
                   gtk_entry_get_text(GTK_ENTRY(state.entry)));
    } else if (state.closeScenario && state.readyToClose) {
        state.success = true;
        writeValue(state.artifactDirectory + "/final.txt", "closed");
    }
    gtk_main_quit();
}

} // namespace

int main(int argc, char **argv) {
    if (!gtk_init_check(&argc, &argv)) {
        return EXIT_FAILURE;
    }

    const char *artifactDirectory = std::getenv("KEYKEY_E2E_CASE_DIR");
    const char *expectedCommit = std::getenv("KEYKEY_E2E_EXPECTED_COMMIT");
    const char *expectedLiteral = std::getenv("KEYKEY_E2E_EXPECTED_LITERAL");
    const char *requiredPreedits = std::getenv("KEYKEY_E2E_REQUIRED_PREEDITS");
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
    GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    state.window = window;
    gtk_window_set_title(
        GTK_WINDOW(window),
        windowTitle == nullptr || *windowTitle == '\0'
            ? "chichi77-keykey-gtk3-e2e"
            : windowTitle);
    gtk_window_set_default_size(GTK_WINDOW(window), 480, 100);
    g_signal_connect(window, "destroy", G_CALLBACK(onDestroy), &state);

    EntryState firstEntryState{
        &state, focusScenario || editingScenario ? "first" : ""};
    EntryState secondEntryState{&state, "second"};
    EntryState thirdEntryState{&state, "third"};
    state.entry = gtk_entry_new();
    state.firstEntry = state.entry;
    gtk_entry_set_placeholder_text(GTK_ENTRY(state.firstEntry),
                                   "Keyboard input must arrive through the IME");
    g_signal_connect(state.firstEntry, "preedit-changed",
                     G_CALLBACK(onPreeditChanged), &firstEntryState);
    g_signal_connect(state.firstEntry, "changed", G_CALLBACK(onTextChanged),
                     &firstEntryState);
    if (holdScenario) {
        g_signal_connect(state.firstEntry, "focus-in-event",
                         G_CALLBACK(onFocusEvent), &firstEntryState);
        g_signal_connect(state.firstEntry, "focus-out-event",
                         G_CALLBACK(onFocusEvent), &firstEntryState);
    }

    if (focusScenario || editingScenario) {
        GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 8);
        state.secondEntry = gtk_entry_new();
        gtk_entry_set_placeholder_text(
            GTK_ENTRY(state.secondEntry),
            editingScenario ? "Password input context"
                            : "Second independent input context");
        g_signal_connect(state.firstEntry, "focus-in-event",
                         G_CALLBACK(onFocusEvent), &firstEntryState);
        g_signal_connect(state.firstEntry, "focus-out-event",
                         G_CALLBACK(onFocusEvent), &firstEntryState);
        g_signal_connect(state.secondEntry, "preedit-changed",
                         G_CALLBACK(onPreeditChanged), &secondEntryState);
        g_signal_connect(state.secondEntry, "changed", G_CALLBACK(onTextChanged),
                         &secondEntryState);
        g_signal_connect(state.secondEntry, "focus-in-event",
                         G_CALLBACK(onFocusEvent), &secondEntryState);
        g_signal_connect(state.secondEntry, "focus-out-event",
                         G_CALLBACK(onFocusEvent), &secondEntryState);
        gtk_box_pack_start(GTK_BOX(box), state.firstEntry, TRUE, TRUE, 0);
        gtk_box_pack_start(GTK_BOX(box), state.secondEntry, TRUE, TRUE, 0);
        if (editingScenario) {
            gtk_entry_set_text(GTK_ENTRY(state.firstEntry), "甲乙丙");
            g_signal_connect(state.firstEntry, "notify::selection-bound",
                             G_CALLBACK(onSelectionChanged), &firstEntryState);
            g_timeout_add(20, pollFirstSelection, &firstEntryState);
            gtk_entry_set_visibility(GTK_ENTRY(state.secondEntry), FALSE);
            gtk_entry_set_input_purpose(GTK_ENTRY(state.secondEntry),
                                        GTK_INPUT_PURPOSE_PASSWORD);

            state.thirdEntry = gtk_entry_new();
            gtk_entry_set_text(GTK_ENTRY(state.thirdEntry), "唯讀");
            gtk_editable_set_editable(GTK_EDITABLE(state.thirdEntry), FALSE);
            gtk_entry_set_placeholder_text(GTK_ENTRY(state.thirdEntry),
                                           "Read-only input context");
            g_signal_connect(state.thirdEntry, "preedit-changed",
                             G_CALLBACK(onPreeditChanged), &thirdEntryState);
            g_signal_connect(state.thirdEntry, "changed",
                             G_CALLBACK(onTextChanged), &thirdEntryState);
            g_signal_connect(state.thirdEntry, "focus-in-event",
                             G_CALLBACK(onFocusEvent), &thirdEntryState);
            g_signal_connect(state.thirdEntry, "focus-out-event",
                             G_CALLBACK(onFocusEvent), &thirdEntryState);
            g_signal_connect(state.thirdEntry, "key-press-event",
                             G_CALLBACK(onKeyPress), &thirdEntryState);
            gtk_box_pack_start(GTK_BOX(box), state.thirdEntry, TRUE, TRUE, 0);
        }
        gtk_container_add(GTK_CONTAINER(window), box);
    } else {
        gtk_container_add(GTK_CONTAINER(window), state.firstEntry);
    }

    gtk_widget_show_all(window);
    gtk_widget_grab_focus(state.firstEntry);
    if (focusScenario || editingScenario) {
        g_idle_add(writeEntryCentersOnIdle, &state);
    }
    if (closeScenario || holdScenario) {
        g_timeout_add(20, onControlFile, &state);
    }
    g_timeout_add_seconds(20, onTimeout, &state);
    gtk_main();

    appendEvent(state, "result", state.success ? "passed" : "failed");
    return state.success ? EXIT_SUCCESS : EXIT_FAILURE;
}
