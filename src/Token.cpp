#include "Token.h"

#include <utility>

Token::Token(const TokenType type, const std::string_view lexeme, const fs::path& file, const std::uint32_t line) {
    this->type = type;
    this->lexeme = lexeme;
    this->file = file;
    this->line = line;
}

Token::~Token() = default;
