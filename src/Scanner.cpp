#include "Scanner.h"

#include <fstream>

Scanner::Scanner(const fs::directory_iterator &path) {
    initialize_keywords();
    this->source = read_file(path);
    this->file = path->path();
    this->tokens = std::vector<TokenType>{};
}

std::vector<Token> Scanner::scan_tokens() {
    while (!is_at_end()) {
        start = current;
        scan_token();
    }

    tokens.push_back(Token(TokenType::END_OF_FILE, "", file, line));
    return tokens;
}

void Scanner::scan_token() {
    char c = advance();

    switch (c) {
        case '(': {
            add_token(TokenType::LEFT_PAREN);
            break;
        }
        case ')': {
            add_token(TokenType::RIGHT_PAREN);
            break;
        }
        case '>': {
            add_token(TokenType::RIGHT_CARET);
            break;
        }
    }
}

bool Scanner::is_at_end() const { return current > source.length(); }

char Scanner::advance() { return source[current++]; }

void Scanner::add_token(const TokenType type) { add_token(type, ""); }


void Scanner::add_token(const TokenType type, const std::string_view lexeme) {
    tokens.push_back(Token{type, lexeme, file, line});
}

std::string Scanner::read_file(const fs::directory_iterator &path) {
    auto line = std::string{};
    auto text = std::string{};

    auto input = std::ifstream{};
    input.open(path->path());

    if (input.is_open()) {
        while (std::getline(input, line)) {
            text += line + 'n';
        }
    }
    input.close();

    return text;
}

void Scanner::initialize_keywords() {
    if (!keywords.empty()) return;

    keywords["def"] = TokenType::DEF;
    keywords["return"] = TokenType::RETURN;
    keywords["if"] = TokenType::IF;
    keywords["else"] = TokenType::ELSE;
    keywords["while"] = TokenType::WHILE;
    keywords["do"] = TokenType::DO;
    keywords["until"] = TokenType::UNTIL;
    keywords["for"] = TokenType::FOR;
    keywords["in"] = TokenType::IN;
    keywords["as"] = TokenType::AS;
    keywords["true"] = TokenType::TRUE;
    keywords["false"] = TokenType::FALSE;
}
