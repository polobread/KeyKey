#include "keykey/linux_ime/smart_mandarin_user_data.h"

#include <iostream>
#include <string>

using keykey::linux_ime::SmartMandarinUserData;

int main(int argc, char **argv) {
    const auto data = SmartMandarinUserData::open(
        SmartMandarinUserData::defaultPath());
    if (!data) {
        std::cerr << "無法開啟好打注音使用者資料庫\n";
        return 1;
    }
    if (argc == 2 && std::string(argv[1]) == "list") {
        for (const auto &entry : data->phrases()) {
            std::cout << entry.first << '\t' << entry.second << '\n';
        }
        return 0;
    }
    if (argc == 2 && std::string(argv[1]) == "reset-learning") {
        if (data->resetLearning()) {
            std::cout << "已清除選字學習紀錄；自訂詞已保留。\n";
            return 0;
        }
        std::cerr << "無法清除學習紀錄\n";
        return 1;
    }
    if (argc == 4 && std::string(argv[1]) == "add") {
        if (data->addPhrase(argv[2], argv[3])) {
            std::cout << "已加入自訂詞。\n";
            return 0;
        }
        std::cerr << "無法加入自訂詞；請檢查注音音節數或詞是否已存在。\n";
        return 1;
    }
    if (argc == 4 && std::string(argv[1]) == "remove") {
        if (data->removePhrase(argv[2], argv[3])) {
            std::cout << "已刪除自訂詞。\n";
            return 0;
        }
        std::cerr << "找不到指定的自訂詞。\n";
        return 1;
    }
    std::cerr << "用法:\n"
                 "  keykey-smart-phrases list\n"
                 "  keykey-smart-phrases add 詞語 'ㄘˊ ㄩˇ'\n"
                 "  keykey-smart-phrases remove 詞語 'ㄘˊ ㄩˇ'\n"
                 "  keykey-smart-phrases reset-learning\n";
    return 2;
}
