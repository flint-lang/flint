#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <utility>

namespace fs = std::filesystem;

using uint32 = std::uint32_t;

enum class TokenType {
    // Scoping tokens
    INDENT, DEDENT,

    //Single character tokens
    LEFT_PAREN, RIGHT_PAREN,
    COMMA, DOT, SEMICOLON, SLASH, PERCENT,
    QUESTION_MARK, DOLLAR,

    //One or two character tokens
    BANG, BANG_EQUAL,
    EQUAL, EQUAL_EQUAL,
    RIGHT_CARET, LESS_EQUAL,
    MINUS, ARROW, MINUS_EQUAL,
    COLON, COLON_EQUAL,
    PLUS, PLUS_EQUAL,
    STAR, POWER,

    //One or n character tokens
    LEFT_CARET, GREATER_EQUAL, SWAP,

    //Literals
    IDENTIFIER, STRING, NUMBER,

    //Keywords
    DEF, RETURN, IF, ELSE, WHILE, DO, UNTIL,
    FOR, IN, AS, TRUE, FALSE,

    END_OF_FILE
};

class Token final {
    const TokenType type;
    const std::string_view lexeme;
    const fs::path file;
    const uint32 line;

public:
    Token(const TokenType type, const std::string_view &lexeme, fs::path file, const uint32 line)
    : type(type), lexeme(lexeme),file(std::move(file)), line(line) {}

    [[nodiscard]] TokenType get_type() const noexcept { return type; }

    [[nodiscard]] std::string get_lexeme() const noexcept { return std::string{lexeme.data()}; }

    [[nodiscard]] fs::path get_file() const noexcept { return file; }

    [[nodiscard]] uint32 get_line() const noexcept { return line; }

    [[nodiscard]] std::string type_string() const noexcept;

    [[nodiscard]] std::string string() const noexcept;

    ~Token() = default;
};
