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
            //if (it->exists() && it->is_character_file()) {
                std::cout << "Parsing file: " << *it << std::endl;
                auto sc = Scanner(it);
                for (auto tokens = sc.scan_tokens(); const auto& token : tokens) {
                    std::cout << token.string() << std::endl;
                }
            //}
        }
    } else {
        std::cout << "The current directory is empty, abandoning..." << std::endl;
        exit(64);
    }

    std::cout << "Press Enter to continue...";
    std::cin.get();

    return 0;
}
