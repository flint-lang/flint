#include "Scanner.h"

#include <fstream>
#include <iostream>

#include "Flint.h"

std::map<std::string, TokenType> Scanner::keywords;

Scanner::Scanner(const fs::directory_iterator &path) {
    if (keywords.empty()) initialize_keywords();
    source = read_file(path);
    file = path->path();
    tokens = std::vector<Token>{};
}

std::vector<Token> &Scanner::scan_tokens() {
    while (!is_at_end()) {
        start = current;
        scan_token();
    }

    tokens.emplace_back(TokenType::END_OF_FILE, "", file, line);
    return tokens;
}

void Scanner::scan_token() {
    switch (const char c = advance()) {
        case '(': {
            add_token(TokenType::LEFT_PAREN);
            break;
        }
        case ')': {
            add_token(TokenType::RIGHT_PAREN);
            break;
        }
        case ',': {
            add_token(TokenType::COMMA);
            break;
        }
        case '.': {
            add_token(TokenType::DOT);
            break;
        }
        case '%': {
            add_token(TokenType::PERCENT);
            break;
        }
        case '?': {
            add_token(TokenType::QUESTION_MARK);
            break;
        }
        case '$': {
            add_token(TokenType::DOLLAR);
            break;
        }
        case ';': {
            add_token(TokenType::SEMICOLON);
            break;
        }
        case '+': {
            add_token(match('=') ? TokenType::PLUS_EQUAL : TokenType::PLUS);
            break;
        }
        case '*': {
            add_token(match('*') ? TokenType::POWER : TokenType::STAR);
            break;
        }
        case '!': {
            add_token(match('=') ? TokenType::BANG_EQUAL : TokenType::BANG);
            break;
        }
        case '=': {
            add_token(match('=') ? TokenType::EQUAL_EQUAL : TokenType::EQUAL);
            break;
        }
        case '>': {
            add_token(match('=') ? TokenType::LESS_EQUAL : TokenType::RIGHT_CARET);
            break;
        }
        case '-': {
            if (match('>'))
                add_token(TokenType::ARROW);
            else if (match('='))
                add_token(TokenType::MINUS_EQUAL);
            add_token(TokenType::MINUS);
            break;
        }
        case ':': {
            add_token(match('=') ? TokenType::COLON_EQUAL : TokenType::COLON);
            break;
        }
        case '<': {
            if (match('-') && match('>')) add_token(TokenType::SWAP);
            add_token(match('=') ? TokenType::GREATER_EQUAL : TokenType::LEFT_CARET);
            break;
        }
        case '/': {
            if (match('/')) {
                // Single-line comment
                while (peek() != '\n' && !is_at_end()) advance();
            } else if (match('*')) {
                // Multi-line comment
                while (!(peek() == '*' && peek_next() == '/') && !is_at_end()) {
                    if (peek() == '\n') line++;
                    advance();
                }

                if (!is_at_end()) {
                    advance(); // Consume '*'
                    advance(); // Consume '/'
                }
            } else {
                add_token(TokenType::SLASH);
            }
            break;
        }
        case ' ':
        case '\r':
        case '\t':
            break;
        case '\n': {
            line++;
            break;
        }
        case '"': {
            string();
            break;
        }
        default: {
            if (isdigit(c))
                number();
            else if (isalpha(c))
                identifier();
            else
                Flint::error(line, source.substr(start, 20), "Unexpected token", file.filename().string());
        }
    }
}

bool Scanner::is_at_end() const { return current > source.length() - 1; }

bool Scanner::match(const char expected) {
    if (is_at_end()) return false;
    if (source[current] != expected) return false;

    current++;
    return true;
}

char Scanner::advance() { return source[current++]; }

char Scanner::peek() const {
    if (is_at_end()) return '\0';
    return source[current];
}

char Scanner::peek_next() const {
    if (current + 1 > source.length()) return '\0';
    return source[current + 1];
}

void Scanner::add_token(const TokenType type) { add_token(type, ""); }

void Scanner::add_token(const TokenType type, const std::string &lexeme) {
    tokens.emplace_back(type, lexeme, file, line);
}

void Scanner::identifier() {
    while (isalpha(peek())) advance();

    if (const std::string text = source.substr(start, current - start); keywords.contains(text)) {
        add_token(keywords[text]);
    } else {
        add_token(TokenType::IDENTIFIER, text);
    }
}

void Scanner::number() {
    while (isdigit(peek())) advance();

    if (peek() == '.' && isdigit(peek_next())) {
        // Consume the .
        advance();

        while (isdigit(peek())) advance();
    }

    add_token(TokenType::NUMBER, source.substr(start, current - start));
}

void Scanner::string() {
    while (peek() != '"' && !is_at_end()) {
        if (peek() == '\n') line++;
        advance();
    }

    if (is_at_end()) {
        Flint::error(line, "at the end of the file", "Unterminated string", file.filename().string());
    }

    //The closing "
    advance();

    const auto value = source.substr(start + 1, current - start - 2);
    add_token(TokenType::STRING, value);
}

std::string Scanner::read_file(const fs::directory_iterator &path) {
    auto line = std::string{};
    auto text = std::string{};

    auto input = std::ifstream{};
    input.open(path->path());

    if (input.is_open()) {
        while (std::getline(input, line)) {
            text += line + '\n';
        }
    }
    input.close();

    return text;
}

void Scanner::initialize_keywords() {
    keywords = std::map<std::string, TokenType>{
        {"def", TokenType::DEF},
        {"return", TokenType::RETURN},
        {"if", TokenType::IF},
        {"else", TokenType::ELSE},
        {"while", TokenType::WHILE},
        {"do", TokenType::DO},
        {"until", TokenType::UNTIL},
        {"for", TokenType::FOR},
        {"in", TokenType::IN},
        {"as", TokenType::AS},
        {"true", TokenType::TRUE},
        {"false", TokenType::FALSE}
    };

}
