#include <QApplication>
#include <QFocusEvent>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QInputMethodEvent>
#include <QInputMethod>
#include <QKeyEvent>
#include <QKeySequence>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>

#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct TestState;

class TestLineEdit final : public QLineEdit {
public:
    TestLineEdit(TestState &state, std::string name, QWidget *parent = nullptr);
    QRect testCursorRect() const { return cursorRect(); }

protected:
    void inputMethodEvent(QInputMethodEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;

private:
    TestState &state_;
    std::string name_;
};

class TestReadOnlyTextEdit final : public QPlainTextEdit {
public:
    explicit TestReadOnlyTextEdit(TestState &state, QWidget *parent = nullptr);

protected:
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;
    void inputMethodEvent(QInputMethodEvent *event) override;
    void focusInEvent(QFocusEvent *event) override;
    void focusOutEvent(QFocusEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;

private:
    TestState &state_;
};

struct TestState {
    QWidget *window = nullptr;
    TestLineEdit *text = nullptr;
    TestLineEdit *firstText = nullptr;
    TestLineEdit *secondText = nullptr;
    TestReadOnlyTextEdit *thirdText = nullptr;
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

std::string utf8(const QString &value) {
    return value.toUtf8().toStdString();
}

std::string jsonString(const std::string &value) {
    std::ostringstream output;
    output << '"';
    for (const char rawCharacter : value) {
        const auto character = static_cast<unsigned char>(rawCharacter);
        switch (character) {
        case '"': output << "\\\""; break;
        case '\\': output << "\\\\"; break;
        case '\b': output << "\\b"; break;
        case '\f': output << "\\f"; break;
        case '\n': output << "\\n"; break;
        case '\r': output << "\\r"; break;
        case '\t': output << "\\t"; break;
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
    jsonOutput << "{\"source\":\"qt6-host\",\"type\":"
               << jsonString(type) << ",\"value\":" << jsonString(value)
               << "}\n";
    const std::string event = type + "=" + value;
    if (state.nextRequiredEvent < state.requiredEvents.size() &&
        event == state.requiredEvents[state.nextRequiredEvent]) {
        ++state.nextRequiredEvent;
    }
}

std::string eventType(const std::string &name, const std::string &event) {
    return name.empty() ? event : name + "-" + event;
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
    const std::string first = utf8(state.firstText->text());
    const std::string second = utf8(state.secondText->text());
    const std::string third = state.thirdText == nullptr
                                  ? std::string{}
                                  : utf8(state.thirdText->toPlainText());
    if (first != state.expectedFirst || second != state.expectedSecond ||
        (state.editingScenario && third != state.expectedThird)) {
        return;
    }
    state.success = true;
    writeValue(state.artifactDirectory + "/final.txt",
               state.editingScenario ? first + "\t" + second + "\t" + third
                                     : first + "\t" + second);
    QApplication::quit();
}

void observeFirstSelection(TestState &state) {
    const int start = state.firstText->selectionStart();
    const int length = static_cast<int>(state.firstText->selectedText().size());
    const std::string value =
        start >= 0 ? std::to_string(start) + ":" +
                         std::to_string(start + length)
                   : "cursor:" +
                         std::to_string(state.firstText->cursorPosition());
    if (value == state.lastFirstSelectionState) {
        return;
    }
    state.lastFirstSelectionState = value;
    writeValue(state.artifactDirectory + "/first-selection-state.txt",
               value + "\n");
    if (start >= 0) {
        appendEvent(state, "first-selection", value);
        completeMultiTextScenarioIfReady(state);
    }
}

void onPreedit(TestState &state, const std::string &name,
               const QString &preedit) {
    const std::string value = utf8(preedit);
    appendEvent(state, eventType(name, "preedit"), value);
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

void onTextChanged(TestState &state, const std::string &name,
                   const QString &text) {
    const std::string value = utf8(text);
    appendEvent(state, eventType(name, "text"), value);
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
        QApplication::quit();
    }
}

TestLineEdit::TestLineEdit(TestState &state, std::string name, QWidget *parent)
    : QLineEdit(parent), state_(state), name_(std::move(name)) {
    QObject::connect(this, &QLineEdit::textChanged, this,
                     [this](const QString &value) {
                         onTextChanged(state_, name_, value);
                     });
}

void TestLineEdit::inputMethodEvent(QInputMethodEvent *event) {
    onPreedit(state_, name_, event->preeditString());
    QLineEdit::inputMethodEvent(event);
}

void TestLineEdit::focusInEvent(QFocusEvent *event) {
    QLineEdit::focusInEvent(event);
    appendEvent(state_, eventType(name_, "focus"), "in");
    completeMultiTextScenarioIfReady(state_);
}

void TestLineEdit::focusOutEvent(QFocusEvent *event) {
    QLineEdit::focusOutEvent(event);
    appendEvent(state_, eventType(name_, "focus"), "out");
    completeMultiTextScenarioIfReady(state_);
}

void TestLineEdit::keyPressEvent(QKeyEvent *event) {
    std::string value = utf8(event->text());
    if (value.empty()) {
        value = utf8(QKeySequence(event->key()).toString());
    }
    appendEvent(state_, eventType(name_, "key-press"), value);
    QLineEdit::keyPressEvent(event);
    if (state_.editingScenario) {
        QTimer::singleShot(0, [this] {
            completeMultiTextScenarioIfReady(state_);
        });
    }
}

TestReadOnlyTextEdit::TestReadOnlyTextEdit(TestState &state, QWidget *parent)
    : QPlainTextEdit(parent), state_(state) {
    QObject::connect(this, &QPlainTextEdit::textChanged, this, [this] {
        onTextChanged(state_, "third", toPlainText());
    });
}

QVariant
TestReadOnlyTextEdit::inputMethodQuery(Qt::InputMethodQuery query) const {
    if (query == Qt::ImEnabled) {
        return false;
    }
    return QPlainTextEdit::inputMethodQuery(query);
}

void TestReadOnlyTextEdit::inputMethodEvent(QInputMethodEvent *event) {
    onPreedit(state_, "third", event->preeditString());
    QPlainTextEdit::inputMethodEvent(event);
}

void TestReadOnlyTextEdit::focusInEvent(QFocusEvent *event) {
    QPlainTextEdit::focusInEvent(event);
    // Qt's text editors re-enable input-method events as focus enters even
    // when the document is read-only. Publish the final read-only state after
    // the base focus handler so the platform input context can disable the IME.
    setAttribute(Qt::WA_InputMethodEnabled, false);
    QGuiApplication::inputMethod()->update(Qt::ImEnabled | Qt::ImHints);
    appendEvent(state_, "third-focus", "in");
    completeMultiTextScenarioIfReady(state_);
}

void TestReadOnlyTextEdit::focusOutEvent(QFocusEvent *event) {
    QPlainTextEdit::focusOutEvent(event);
    appendEvent(state_, "third-focus", "out");
    completeMultiTextScenarioIfReady(state_);
}

void TestReadOnlyTextEdit::keyPressEvent(QKeyEvent *event) {
    std::string value = utf8(event->text());
    if (value.empty()) {
        value = utf8(QKeySequence(event->key()).toString());
    }
    appendEvent(state_, "third-key-press", value);
    QPlainTextEdit::keyPressEvent(event);
    QTimer::singleShot(0, [this] {
        completeMultiTextScenarioIfReady(state_);
    });
}

bool writeTextCenter(const TestState &state, QWidget *text,
                     const std::string &name) {
    if (!text->isVisible() || text->width() <= 0 || text->height() <= 0) {
        return false;
    }
    const QPoint point = text->mapTo(
        state.window, QPoint(text->width() / 2, text->height() / 2));
    writeValue(state.artifactDirectory + "/" + name + "-center.txt",
               std::to_string(point.x()) + " " + std::to_string(point.y()) +
                   "\n");
    return true;
}

bool writeSecondCharacterSelectionPoints(TestState &state) {
    if (state.firstText->text().size() < 3) {
        return false;
    }
    const int savedPosition = state.firstText->cursorPosition();
    state.firstText->setCursorPosition(1);
    const QPoint start = state.firstText->mapTo(
        state.window, state.firstText->testCursorRect().center());
    state.firstText->setCursorPosition(2);
    const QPoint end = state.firstText->mapTo(
        state.window, state.firstText->testCursorRect().center());
    state.firstText->setCursorPosition(savedPosition);
    writeValue(state.artifactDirectory + "/first-selection-start.txt",
               std::to_string(start.x()) + " " + std::to_string(start.y()) +
                   "\n");
    writeValue(state.artifactDirectory + "/first-selection-end.txt",
               std::to_string(end.x()) + " " + std::to_string(end.y()) +
                   "\n");
    return true;
}

bool writeTextCenters(TestState &state) {
    if (!writeTextCenter(state, state.firstText, "first") ||
        !writeTextCenter(state, state.secondText, "second") ||
        (state.editingScenario &&
         (!writeTextCenter(state, state.thirdText, "third") ||
          !writeSecondCharacterSelectionPoints(state)))) {
        return false;
    }
    return true;
}

const char *environment(const char *name) {
    const char *value = std::getenv(name);
    return value == nullptr ? "" : value;
}

} // namespace

int main(int argc, char **argv) {
    QApplication application(argc, argv);
    application.setQuitOnLastWindowClosed(false);

    const std::string artifactDirectory = environment("KEYKEY_E2E_CASE_DIR");
    const std::string expectedCommit =
        environment("KEYKEY_E2E_EXPECTED_COMMIT");
    const std::string expectedLiteral =
        environment("KEYKEY_E2E_EXPECTED_LITERAL");
    const char *requiredPreeditsEnvironment =
        std::getenv("KEYKEY_E2E_REQUIRED_PREEDITS");
    const std::string requiredPreedits = requiredPreeditsEnvironment == nullptr
                                             ? ""
                                             : requiredPreeditsEnvironment;
    const std::string scenario = environment("KEYKEY_E2E_SCENARIO");
    const bool focusScenario = scenario == "focus";
    const bool editingScenario = scenario == "editing";
    const bool closeScenario = scenario == "close";
    const bool holdScenario = scenario == "hold";
    const std::string expectedFirst =
        environment("KEYKEY_E2E_EXPECTED_FIRST");
    const std::string expectedSecond =
        environment("KEYKEY_E2E_EXPECTED_SECOND");
    const std::string expectedThird =
        environment("KEYKEY_E2E_EXPECTED_THIRD");
    const std::string requiredEvents =
        environment("KEYKEY_E2E_REQUIRED_EVENTS");
    if (artifactDirectory.empty() ||
        (!focusScenario && !editingScenario && !closeScenario &&
         !holdScenario &&
         (expectedCommit.empty() || requiredPreeditsEnvironment == nullptr)) ||
        (closeScenario && requiredPreedits.empty()) ||
        ((focusScenario || editingScenario) &&
         (expectedFirst.empty() || expectedSecond.empty())) ||
        (editingScenario && expectedThird.empty())) {
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
        state.expectedThird = expectedThird;
        if (!requiredEvents.empty()) {
            state.requiredEvents = split(requiredEvents, ';');
        }
    } else if (!closeScenario && !holdScenario) {
        state.expectedCommit = expectedCommit;
        state.expectedLiteral = expectedLiteral;
    }
    if (!focusScenario && !editingScenario && !requiredPreedits.empty()) {
        state.requiredPreedits = split(requiredPreedits, ',');
    }

    QWidget window;
    state.window = &window;
    const std::string requestedTitle = environment("KEYKEY_E2E_WINDOW_TITLE");
    window.setWindowTitle(QString::fromUtf8(
        requestedTitle.empty() ? "chichi77-keykey-qt6-e2e"
                               : requestedTitle.c_str()));
    window.resize(focusScenario ? 960 : 480, editingScenario ? 160 : 100);

    const std::string firstName =
        focusScenario || editingScenario ? "first" : "";
    auto *firstText = new TestLineEdit(state, firstName, &window);
    state.text = firstText;
    state.firstText = firstText;
    firstText->setPlaceholderText(
        QStringLiteral("Keyboard input must arrive through the IME"));

    QBoxLayout *layout = nullptr;
    if (focusScenario) {
        layout = new QHBoxLayout(&window);
    } else {
        layout = new QVBoxLayout(&window);
    }
    layout->addWidget(firstText);

    if (focusScenario || editingScenario) {
        auto *secondText = new TestLineEdit(state, "second", &window);
        state.secondText = secondText;
        secondText->setPlaceholderText(
            editingScenario ? QStringLiteral("Password input context")
                            : QStringLiteral("Second independent input context"));
        layout->addWidget(secondText);
        if (editingScenario) {
            firstText->setText(QStringLiteral("甲乙丙"));
            QObject::connect(firstText, &QLineEdit::selectionChanged,
                             [&state] { observeFirstSelection(state); });
            secondText->setEchoMode(QLineEdit::Password);
            secondText->setInputMethodHints(
                Qt::ImhHiddenText | Qt::ImhSensitiveData);
            auto *thirdText = new TestReadOnlyTextEdit(state, &window);
            state.thirdText = thirdText;
            thirdText->setPlainText(QStringLiteral("唯讀"));
            thirdText->setReadOnly(true);
            thirdText->setPlaceholderText(
                QStringLiteral("Read-only input context"));
            layout->addWidget(thirdText);
        }
    }

    window.show();
    firstText->setFocus(Qt::OtherFocusReason);
    if (focusScenario || editingScenario) {
        auto *geometryTimer = new QTimer(&window);
        geometryTimer->setInterval(20);
        QObject::connect(geometryTimer, &QTimer::timeout, [&state, geometryTimer] {
            if (writeTextCenters(state)) {
                geometryTimer->stop();
            }
        });
        geometryTimer->start();
    }
    if (editingScenario) {
        auto *selectionTimer = new QTimer(&window);
        selectionTimer->setInterval(20);
        QObject::connect(selectionTimer, &QTimer::timeout,
                         [&state] { observeFirstSelection(state); });
        selectionTimer->start();
    }
    if (closeScenario || holdScenario) {
        auto *controlTimer = new QTimer(&window);
        controlTimer->setInterval(20);
        QObject::connect(controlTimer, &QTimer::timeout,
                         [&state, controlTimer] {
            std::ifstream input(state.artifactDirectory + "/close-now",
                                std::ios::binary);
            if (!input.good()) {
                return;
            }
            controlTimer->stop();
            appendEvent(state, "close-command", "received");
            if (state.holdScenario) {
                state.success = true;
                writeValue(state.artifactDirectory + "/final.txt",
                           utf8(state.text->text()));
            } else if (state.closeScenario && state.readyToClose) {
                state.success = true;
                writeValue(state.artifactDirectory + "/final.txt", "closed");
            }
            state.window->close();
            QApplication::quit();
        });
        controlTimer->start();
    }
    QTimer::singleShot(20000, [&state] {
        if (state.focusScenario || state.editingScenario) {
            const std::string first = utf8(state.firstText->text());
            const std::string second = utf8(state.secondText->text());
            appendEvent(state, "timeout-first-text", first);
            appendEvent(state, "timeout-second-text", second);
            if (state.editingScenario) {
                const std::string third =
                    utf8(state.thirdText->toPlainText());
                appendEvent(state, "timeout-third-text", third);
                writeValue(state.artifactDirectory + "/final.txt",
                           first + "\t" + second + "\t" + third);
            } else {
                writeValue(state.artifactDirectory + "/final.txt",
                           first + "\t" + second);
            }
        } else {
            const std::string value = utf8(state.text->text());
            appendEvent(state, "timeout-text", value);
            writeValue(state.artifactDirectory + "/final.txt", value);
        }
        state.timedOut = true;
        QApplication::quit();
    });

    application.exec();
    appendEvent(state, "result", state.success ? "passed" : "failed");
    return state.success ? EXIT_SUCCESS : EXIT_FAILURE;
}
