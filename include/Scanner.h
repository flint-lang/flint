#pragma once

#include <filesystem>
#include <map>
#include <string>
#include <vector>

#include "Token.h"

namespace fs = std::filesystem;

class Scanner {
    static std::map<std::string, TokenType> keywords;

    auto tokens = std::vector<Token>{};

    int start = 0;
    int current = 0;
    fs::path file;
    std::uint32_t line = 1;

    std::string source;

public:
    explicit Scanner(const fs::directory_iterator &path);

    std::vector<Token> &scan_tokens();

private:
    void scan_token();

    [[nodiscard]] bool is_at_end() const;

    [[nodiscard]] bool match(char expected);

    char advance();

    [[nodiscard]] char peek() const;

    [[nodiscard]] char peek_next() const;

    void add_token(TokenType type);

    void add_token(TokenType type, const std::string& lexeme);

    void identifier();

    void number();

    void string();

    static std::string read_file(const fs::directory_iterator &path);

    static void initialize_keywords();
};
