#include <filesystem>
#include <iostream>

namespace fs = std::filesystem;

int main()
{
    const auto current_path = fs::current_path();

    std::cout << "Current working directory: " << current_path << std::endl;

    std::cout << "Files in working directory:" << std::endl;
    for(auto it = fs::directory_iterator(current_path); it != fs::directory_iterator{}; ++it) {
        std::cout << '\t' << *it << std::endl;
    }

    std::cout << "Press Enter to continue...";
    std::cin.get();

    return 0;
}
