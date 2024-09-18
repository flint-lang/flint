#include "Flint.h"

#include <iostream>
#include <format>

namespace Flint {
    void error(const uint32 line, const std::string &message, const std::string &file) {
        report(line, "", message, file);
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

    void report(uint32 line, const std::string &where, const std::string &message, const std::string &file) {
        std::cerr << std::format("[{}] Line: {} Error {}: {}\n", file, line, where, message);
        std::cerr << "Abandoning..." << std::endl;
        exit(42);
    }
}
