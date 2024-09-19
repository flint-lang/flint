#pragma once

#include <any>
#include <cstdint>
#include <filesystem>
#include <string>

namespace fs = std::filesystem;

using uint32 = std::uint32_t;

enum class TokenType {
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

class Token {
    TokenType type;
    std::string lexeme;
    std::any literal;
    fs::path file;
    uint32 line;

public:

    Token(TokenType type, const std::string &lexeme, const fs::path &file, uint32 line);

    [[nodiscard]] TokenType get_type() const;

    [[nodiscard]] std::string get_lexeme() const;

    [[nodiscard]] fs::path get_file() const;

    [[nodiscard]] uint32 get_line() const;

    [[nodiscard]] std::string type_string() const;

    [[nodiscard]] std::string string() const;

    ~Token();

};