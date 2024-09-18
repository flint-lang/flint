#include "Flint.h"

#include <filesystem>
#include <format>
#include <iostream>

#include "Scanner.h"

namespace fs = std::filesystem;

int main() {
    const auto current_path = fs::current_path();

    std::cout << "Current working directory: " << current_path << std::endl;

    if (fs::directory_iterator(current_path) != fs::directory_iterator{}) {
        std::cout << "Files in working directory:" << std::endl;

        for (auto it = fs::directory_iterator(current_path); it != fs::directory_iterator{}; ++it) {
            if (it->exists() && it->is_character_file()) {
                std::cout << "Parsing file: " << *it << std::endl;
                auto sc = Scanner(it);
            }
        }
    } else {
        std::cout << "The current directory is empty, abandoning..." << std::endl;
        exit(64);
    }

    std::cout << "Press Enter to continue...";
    std::cin.get();

    return 0;
}

namespace Flint {
    void error(const uint32 line, const std::string &message, const std::string &file) {
        report(line, std::string{}, message, file);
    }

    void error(const Token &token, const std::string &message) {
        if (token.get_type() == TokenType::END_OF_FILE)
            report(token.get_line(), "at end", message, token.get_file().filename().string());
        else
            report(
                token.get_line(),
                "at '" + token.get_lexeme() + "'",
                message,
                token.get_file().filename().string()
            );
    }

    void report(uint32 line, const std::string &where, std::string &message, const std::string &file) {
        std::cerr << std::format("[%s] Line: %d Error: %s\n", file, where, line, message);
        std::cerr << "Abandoning..." << std::endl;
        exit(42);
    }
}
