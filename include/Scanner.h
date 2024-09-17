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

    std::vector<Token> scan_tokens();

private:
    void scan_token();

    [[nodiscard]] bool is_at_end() const;

    char advance();

    void add_token(TokenType type);

    void add_token(TokenType type, std::string_view lexeme);

    static std::string read_file(const fs::directory_iterator &path);

    static void initialize_keywords();
};
